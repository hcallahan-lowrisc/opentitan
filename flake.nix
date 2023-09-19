{
  description = "Provide dependencies to run the OpenTitan project";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
  # inputs.nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nix-filter.url = "github:numtide/nix-filter";
  inputs.poetry2nix.url = "github:nix-community/poetry2nix";
  inputs.poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.poetry2nix.inputs.flake-utils.follows = "flake-utils";
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };

  outputs = inputs@{...} : let
    ##
  in inputs.flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.poetry2nix.overlay
        ];
      };

      poetryArgs = {
        python = pkgs.python3;
        projectDir = pkgs.nix-gitignore.gitignoreSource [] ./.;
        overrides = poetryOverrides;
      };

      # poetry tries to build the python projects based on the information
      # given in their own build description files (setup.py etc.)
      # Sometimes, the inputs are incomplete. Add missing inputs here.
      poetryOverrides = pkgs.poetry2nix.overrides.withDefaults (final: prev: {
        # pip = pkgs.python3.pkgs.pip;
        pyfinite = prev.pyfinite.overridePythonAttrs (old: {
          buildInputs = (old.buildInputs or []) ++ [ prev.setuptools ];
        });
        zipfile2 = prev.zipfile2.overridePythonAttrs (old: {
          buildInputs = (old.buildInputs or []) ++ [ prev.setuptools ];
        });
        # Very slow build.
        mypy = prev.mypy.override {
          preferWheel = true; # use the binary dist
        };
        # Missing rustc/cargo etc.
        # libcst = prev.libcst.overridePythonAttrs (old: {
        #   buildInputs = (old.buildInputs or []) ++ [ prev.setuptools-rust ];
        # });
        libcst = prev.libcst.override {
          preferWheel = true; # use the binary dist
        };
        okonomiyaki = prev.okonomiyaki.overridePythonAttrs (old: {
          buildInputs = (old.buildInputs or []) ++ [ prev.setuptools ];
        });
        simplesat = prev.simplesat.overridePythonAttrs (old: {
          buildInputs = (old.buildInputs or []) ++ [ prev.setuptools ];
        });
        # Some problem building due to a malformed semantic version string.
        isort = prev.isort.override {
          preferWheel = true; # use the binary dist
        };
        fusesoc = prev.fusesoc.overridePythonAttrs (old: {
          buildInputs = (old.buildInputs or []) ++ [ prev.setuptools prev.setuptools-scm ];
        });
        chipwhisperer = prev.chipwhisperer.overridePythonAttrs (old: {
          buildInputs = (old.buildInputs or []) ++ [ prev.setuptools ];
        });
      });

      poetryEnv = pkgs.poetry2nix.mkPoetryEnv poetryArgs;
      poetryPackages = pkgs.poetry2nix.mkPoetryPackages poetryArgs;

    in {
      packages = {
        pythonEnv = poetryEnv;
        pythonPackages = poetryPackages.poetryPackages;
        python = poetryPackages.python;
        hello = pkgs.hello;
      };
      devShells.default = pkgs.mkShellNoCC {
        name = "devShell";
        version = "0.1.0";
        packages =
          with pkgs; [
            hugo doxygen mdbook google-cloud-sdk bazel poetry
          ] ++ [
            poetryEnv
          ];
        USE_BAZEL_VERSION = "${pkgs.bazel.version}"; # 6.3.2
        shellHook = ''
           echo "OpenTitan environment activated."
        '';
      };
    });
}
