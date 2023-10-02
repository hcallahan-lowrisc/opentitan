{
  description = "Provide dependencies to run the OpenTitan project";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
  inputs.nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.poetry2nix.url = "github:nix-community/poetry2nix";
  inputs.poetry2nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };
  inputs.nci.url = "github:yusdacra/nix-cargo-integration";

  outputs = inputs@{ ... } : let
    ##
  in inputs.flake-parts.lib.mkFlake { inherit inputs; } {

    imports = [
      # Import other flake-parts modules here...
      # inputs.devenv.flakeModule
      ./third_party/nixpkgs/poetry.nix
      ./third_party/nixpkgs/nix-cargo-integration.nix
    ];

    systems = [ # systems for which you want to build the `perSystem` attributes
      "x86_64-linux"
    ];

    # 'perSystem' functions similarly to 'flake-utils.lib.eachSystem'
    perSystem = {config, pkgs, inputs', self', system, ...}: {
      devShells.default = pkgs.mkShellNoCC {
        name = "devShell";
        version = "0.1.0";
        packages =
          with pkgs; [
            hugo doxygen mdbook google-cloud-sdk bazel poetry
          ] ++ [
            # Defined in ./third-party/nixpkgs/poetry.nix
            self'.packages.pythonEnv
          ];
        USE_BAZEL_VERSION = "${pkgs.bazel.version}"; # 6.3.2
        shellHook = ''
           echo "OpenTitan environment activated."
        '';
      };
    };

  };
}


