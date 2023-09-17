let
  pkgs = import <nixpkgs> {};
in
pkgs.buildEnv {
  name = "nix-tools";
  paths = with pkgs; [
    # (haskell.packages.ghc822.ghcWithPackages (p: with p; [ {0} ]))
    openjdk
    mdbook
    doxygen
    hugo
  ];
}
