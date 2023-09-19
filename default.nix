let
  nixpkgs = import <nixpkgs> {};
  flake = builtins.getFlake "path:/home/harry/projects/opentitan/";
  packages = flake.outputs.packages.x86_64-linux;
in {
  python = packages.python;
  pkgs = packages.pythonPackages;
}
