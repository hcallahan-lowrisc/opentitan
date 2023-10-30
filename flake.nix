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

  ### LOWRISC ###
  inputs.lowrisc-it = {
    # url = "git+ssh://git@github.com/lowRISC/lowrisc-it.git";
    url = "/home/harry/projects/lowrisc-it/";
    inputs.nixpkgs.follows = "nixpkgs";
  };


  outputs = inputs@{ ... } : let
    ##
  in inputs.flake-parts.lib.mkFlake { inherit inputs; } {

    imports = [
      # Import other flake-parts modules here...
      # inputs.devenv.flakeModule
      # ./third_party/nixpkgs/poetry.nix
    ];

    systems = [
      # systems for which you want to build the `perSystem` attributes
      "x86_64-linux"
      # You can also get systems from elsewhere...
      # systems = nixpkgs.lib.systems.flakeExposed;
      # ...
    ];

    # Put your original flake attributes here.
    # flake = {
    #   # ...
    # };

    # 'perSystem' functions similarly to 'flake-utils.lib.eachSystem'
    perSystem = { config, pkgs, inputs', self', system, ... }: {
      devShells.all = pkgs.mkShellNoCC {
        name = "devShell";
        version = "0.1.0";
        packages =
          with pkgs; [
            hugo doxygen mdbook google-cloud-sdk bazel poetry
          ] ++ [
            inputs'.lowrisc-it.packages.vcs
          ];
        USE_BAZEL_VERSION = "${pkgs.bazel.version}"; # 6.3.2
        shellHook = ''
           echo "OpenTitan environment activated."
        '';
      };
    };

  };
}


