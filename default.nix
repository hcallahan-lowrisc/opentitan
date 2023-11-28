let
  flake = builtins.getFlake (toString ./.);
in
# The function 'nixpkgs_python_repository' takes an input 'nix_file'
# that expects a file returning a two-element set with the following keys:
{
  python = flake.outputs.packages.x86_64-linux.python;
  pkgs = flake.outputs.poetryPackagesList.x86_64-linux;
}
