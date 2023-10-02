{ self, inputs, ... }: {
  _file = ./nix-cargo-integration.nix;

  # # https://flake.parts/options/flake-parts#opt-flake.overlays
  # config.flake.overlays = {
  #   default = self.inputs'.poetry2nix.overlay;
  # };
  imports = [
    inputs.nci.flakeModule
  ];

  config.perSystem = {
    config,
    pkgs,
    inputs',
    self',
    system,
    ...
  }: let

    outputs = config.nci.outputs;

  in
    {
      nci.projects."ot-rust" = {
        path = ../rust;
        export = true;
      };

      packages = {
        #
      };

      devShells.rust = outputs."ot-rust".devShell;
    };
}
