{
  description = "Provide dependencies to run the OpenTitan project";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
  inputs.nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nix-filter.url = "github:numtide/nix-filter";
  # inputs.pypi-deps-db = {
  #   url = "github:DavHau/pypi-deps-db";
  #   flake = false;
  # };
  # inputs.mach-nix = {
  #   url = "mach-nix/master";
  #   inputs.nixpkgs.follows = "nixpkgs-unstable";
  #   inputs.pypi-deps-db.follows = "pypi-deps-db";
  # };

  outputs = inputs@{...} : let
    ##
  in inputs.flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
      # pythonEnv = inputs.mach-nix.lib."${system}".mkPython {
      #   python = "python310";
      #   ignoreDataOutdated = true;
      #   requirements = builtins.readFile ./python-requirements.txt + ''
      #       # additional dependencies for local work
      #     '';
      # };
    in {
      devShells.default = pkgs.mkShellNoCC {
        name = "devShell";
        version = "0.1.0";
        packages = with pkgs; [ hugo doxygen mdbook google-cloud-sdk bazel ];
        USE_BAZEL_VERSION = "${pkgs.bazel.version}"; # 6.3.2
        shellHook = ''
          source /home/harry/scratch/venvs/opentitan/.venv/bin/activate
        '';
      };
    });
}
