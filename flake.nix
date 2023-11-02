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
  };


  outputs = inputs@{ ... } : let
    ##
  in inputs.flake-parts.lib.mkFlake { inherit inputs; } {

    imports = [
      # Import other flake-parts modules here...
      # inputs.devenv.flakeModule
      ./third_party/nixpkgs/poetry.nix
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
    perSystem = { config, pkgs, inputs', self', system, ... }:
      let

        # be = (pkgs.buildFHSEnv {
        #   pname = "be";
        #   version = "0.0.1";
        #   name = null;

        #   targetPkgs = _: with pkgs; [
        #     bash
        #     coreutils
        #     elfutils
        #     stdenv.cc
        #     libxcrypt-legacy
        #     zlib
        #     glibc
        #   ] ++ [
        #     inputs'.lowrisc-it.packages.vcs
        #     self'.packages.pythonEnv
        #   ];
        #   runScript = "bash";
        # }).env;

        garyenv = let
          ncurses5-patched = with pkgs; runCommand "ncurses5" {
            outputs = ["out" "dev" "man"];
          } ''
            cp -r ${ncurses5} $out
            chmod +w $out/lib
            cp -L --no-preserve=mode --remove-destination `realpath $out/lib/libtinfo.so.5` $out/lib/libtinfo.so.5
            ${patchelf}/bin/patchelf --set-soname libtinfo.so.5 $out/lib/libtinfo.so.5
            cp -r ${ncurses5.dev} $dev
            cp -r ${ncurses5.man} $man
          '';
          # vcs = inputs'.lowrisc-it.packages.xcelium;
          eda = inputs'.lowrisc-it.packages.xcelium_old;
        in
          (pkgs.buildFHSEnv {
            name = "opentitan";
            targetPkgs = _:
              with pkgs;
              [
                # For serde-annotate which can be built with just cargo
                rustup

                # Bazel downloads Python Toolchains / Rust compilers which are not patch-elfed
                # -> they need these deps.
                zlib
                openssl
                curl
                perl
                libxcrypt-legacy

                (wrapCCWith {
                  cc = gcc-unwrapped;
                  nixSupport.cc-cflags = ["-fPIC"];
                })

                python3Full
                # (python3.withPackages (ps: [ ps.virtualenv ]))
                srecord
                elfutils

                (pkg-config.override {
                  extraBuildCommands = ''
                    echo "export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/lib/pkgconfig" >> $out/nix-support/add-flags.sh
                  '';
                })
                udev
                libftdi1
                libusb1 # needed for libftdi1 pkg-config
                ncurses5-patched
              ]
              ++ [
                eda # VCS/Xcelium etc.
                time bc
              ];
            extraOutputsToInstall = ["dev"];
            profile = ''
              # Setup the eda-tool environment variables (needed for GUI etc.)
              # Setup an existing python venv (#TODO use nix pythonEnv)
              source /home/harry/scratch/venvs/opentitan/.venv2/bin/activate
            '';
          }).env;

      in {
        devShells.garyenv = garyenv;
        devShells.all = pkgs.mkShellNoCC {
          name = "devShell";
          version = "0.1.0";
          buildInputs = with pkgs; [
            openssl.dev pkg-config
          ];
          packages =
            with pkgs; [
              hugo doxygen mdbook google-cloud-sdk poetry
            ] ++ [
              inputs'.lowrisc-it.packages.vcs
            ] ++ [
              self'.packages.pythonEnv
            ];
          USE_BAZEL_VERSION = "${pkgs.bazel.version}"; # 6.3.2
          shellHook = ''
            # export LD_LIBRARY_PATH="$(pkg-config --cflags openssl | cut -c3-)"
            # echo $LD_LIBRARY_PATH
            echo "OpenTitan environment activated."
          '';
        };
    };

  };
}


