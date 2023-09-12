{ lib, flake-parts-lib, ... }:
let
  inherit (lib)
    mkOption
    types
    ;
  inherit (flake-parts-lib)
    mkTransposedPerSystemModule
    ;
in
mkTransposedPerSystemModule {
  name = "poetryPackagesList";
  option = mkOption {
    type = types.listOf types.package;
    default = {};
    description = ''
      An list of packages as constructed in:
        (poetry2nix.mkPoetryPackages <poetry_args>).poetryPackages
    '';
  };
  file = ./poetryPackagesList.nix;
}
