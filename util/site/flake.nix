{
  description = "A flake for developing and building the OpenTitan site";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.nix-filter.url = "github:numtide/nix-filter";

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
    nix-filter,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import inputs.rust-overlay)];
        };

        proj_root = ./../..;

        my_pythonenv = pkgs.python3.withPackages (ps: with ps; [hjson Mako mistletoe pyyaml libcst tabulate semantic-version]);

        my_rustenv = { inherit (self.rust-bin.stable.latest) rustc cargo rustdoc rust-std; };

        ######################################################
        ### Build the components of the site individually. ###
        ######################################################

        ot-doxygen = {
          doxygen_html_out_dir ? "html/", # The relative path of the generated HTML files to the DOXYGEN_OUT path
        }:
          pkgs.stdenv.mkDerivation rec {
            pname = "ot-doxygen";
            version = "0.0.1-dev";
            src = nix-filter.lib {
              root = proj_root;
              include = [
                # If no include is passed, it will include all the paths.
                "util/doxygen/Doxyfile"
                "site/doxygen"
                "sw/device"
                "hw/top_earlgrey/sw"
              ];
            };
            nativeBuildInputs = with pkgs; [doxygen git];
            dontInstall = true;
            dontFixup = true;
            # outputs = [ "out" "xml" ]; Possible to seperate the xml outputs from the html?
            buildPhase = ''
              # Build up doxygen command
              doxygen_env="env"
              doxygen_env+=" SRCTREE_TOP=."
              doxygen_env+=" DOXYGEN_OUT=$out"
              doxygen_args="util/doxygen/Doxyfile"

              mkdir -p $out
              $doxygen_env doxygen $doxygen_args
            '';
            # TODO: stop doxygen spitting out a bunch of the following errors (not actually fatal it turns out)
            # "fatal: not a git repository (or any of the parent directories): .git"
          };

        ot-landing = {
          baseURL ? "http://localhost:9000",
          docsURL ? "http://localhost:9000/book",
        }:
          pkgs.stdenv.mkDerivation rec {
            pname = "ot-landing";
            version = "0.0.1-dev";
            src = nix-filter.lib {
              root = proj_root;
              include = [
                # If no include is passed, it will include all the paths.
                "site/landing"
                "site/block-diagram"
                "util/site-dashboard"
                "util/site/blocks.json"
              ];
            };
            nativeBuildInputs = [pkgs.hugo];
            dontInstall = true;
            dontFixup = true;
            buildPhase = ''
              hugo_args=""
              hugo_args+=" --source site/landing/"
              hugo_args+=" --destination $out"
              hugo_args+=" --baseURL ${baseURL}"

              # Replace relative symlinks with the real files, as Hugo seems to choke on these for some reason.
              for f in site/landing/static/js/{dashboard.js,ot-nightly-results.js}; do
                  pushd $(dirname $f) &>/dev/null
                  name="$(basename $f)"
                  cp --remove-destination $(readlink $name) $name
                  popd &>/dev/null
              done

              mkdir $out
              hugo $hugo_args
            '';
          };

        ot-book = {
          baseURL ? "http://localhost:9000/book",
          doxyURL ? "http://localhost:9000/gen/doxy/html",
          doxyDrv ? (ot-doxygen {}), # Need the location of the build Doxygen files to import the XML
        }:
          pkgs.stdenv.mkDerivation rec {
            pname = "ot-book";
            version = "0.0.1-dev";
            src = nix-filter.lib.filter {
              root = proj_root;
              # If no include is passed, it will include all the paths.
              exclude = [
                "util/site/flake.nix"
                "util/site/flake.lock"
              ];
            };
            nativeBuildInputs = with pkgs; [mdbook libxslt] ++ [my_pythonenv];
            patchPhase = ''
              runHook prePatch
              patchShebangs --build . &>/dev/null
              runHook postPatch
            '';
            buildPhase = ''
              runHook preBuild

              book_env="env"
              book_env+=" MDBOOK_OUTPUT__HTML__THEME=$(realpath site/book-theme/)"  # mdBook interprets this as relative to SITE_URL unless it is absolute
              book_env+=" MDBOOK_OUTPUT__HTML__DEFAULT_THEME=unicorn-vomit-light"
              book_env+=" MDBOOK_OUTPUT__HTML__PREFERRED_DARK_THEME=unicorn-vomit-light"
              book_env+=" MDBOOK_OUTPUT__HTML__SITE_URL=${baseURL}"
              # Preprocessors
              book_env+=" MDBOOK_PREPROCESSOR__TESTPLAN__COMMAND=util/mdbook_testplan.py"
              book_env+=" MDBOOK_PREPROCESSOR__OTBN__COMMAND=util/mdbook_otbn.py"
              book_env+=" MDBOOK_PREPROCESSOR__REGGEN__COMMAND=util/mdbook_reggen.py"
              book_env+=" MDBOOK_PREPROCESSOR__WAVEJSON__COMMAND=util/mdbook_wavejson.py"
              book_env+=" MDBOOK_PREPROCESSOR__README2INDEX__COMMAND=util/mdbook_readme2index.py"
              book_env+=" MDBOOK_PREPROCESSOR__DASHBOARD__COMMAND=util/mdbook_dashboard.py"
              # book_env+=" MDBOOK_PREPROCESSOR__BLOCK_DASHBOARD__COMMAND=util/mdbook-block-dashboard.py"
              book_env+=" MDBOOK_PREPROCESSOR__DOXYGEN__COMMAND=util/mdbook_doxygen.py"
              book_env+=" MDBOOK_PREPROCESSOR__DOXYGEN__OUT_DIR=${doxyDrv}"
              book_env+=" MDBOOK_PREPROCESSOR__DOXYGEN__HTML_OUT_DIR=${doxyURL}"

              book_args="build"
              book_args+=" --dest-dir $(realpath ./build)"

              # This isn't strictly required, but there is a check in mdbook_doxygen.py that it can find the files here.
              # It confirms that the Doxygen output has been correctly generated for our expected filesystem structure.
              mkdir -p build/gen/doxy
              ln -s ${doxyDrv}/* build/gen/doxy

              mkdir -p ./build
              $book_env mdbook $book_args

              runHook postBuild
            '';
            # Define a custom InstallPhase as mdBook currently copies waay too many files to it's --dest-dir
            installPhase = ''
              runHook preInstall

              mkdir -p $out
              pushd build

              # Manually delete some files in the build tree
              rm -rf sw/vendor/wycheproof

              # Blacklist some top-level directories while copying across
              blacklist="ci quality release rules third_party"
              for f in *; do
                if ! [[ $(grep $f <<< $blacklist) ]]; then
                  cp -R $f $out
                fi
              done

              runHook postInstall
            '';
            dontFixup = true;
          };


        #######################################################
        ### Assemble components into a full site filesystem ###
        #######################################################

        # DON'T FMT #
        site-fs = {
          baseURL ? "http://localhost:9000",
          path ? "",  # Build for a path within the domain.
                      # (e.g. as an alternative to a URL-rewriting reverse-proxy)
        }: {
          symlink ? true
        }: let

          # Create derivations which are specialized with the mappings we want.
          doxygen_html_out_dir = "html/";
          doxygen              = ot-doxygen { inherit doxygen_html_out_dir; };
          landing              = ot-landing { baseURL = "${baseURL}/${path}";
                                              docsURL = "${baseURL}/${path}/book"; };
          book                 = ot-book    { baseURL = "${baseURL}/${path}/book";
                                              doxyURL = "${baseURL}/${path}/gen/doxy/${doxygen_html_out_dir}";
                                              doxyDrv = doxygen; };

          # These are the input derivations and their final filesystem mappings
          cmp = [
            [ landing "" ]
            [ book "book/" ]
            [ doxygen "gen/doxy/" ]
          ];
          # These directories should be excluded from the final build
          blacklist_dirs = [
            [ doxygen [ "api-xml/" ] ] # Would be nice to delete from build, but mdbook_doxygen.py requires it.
          ];

          ### Assemble the buildPhase copy/link commands ###
          ##################################################

          # We want to support optionally constructing the site filesystem from symlinks instead of copies,
          # to support rapid development of the site, and to keep the build-time down.
          # The boolean input "symlink" is used to control this.

          # e.g.
          # symlink=true  : "lndir -silent /nix/store/vvs3bhcnp7jbr9a7yw8rhmndb8nbkacj-ot-landing-0.0.1-dev /nix/store/hdw5358bda0b7g6f8xja7yvdjs3zl4wh-site-fs-0.0.1-dev/pr/12/final_final2/"
          # symlink=false : "cp -R /nix/store/vvs3bhcnp7jbr9a7yw8rhmndb8nbkacj-ot-landing-0.0.1-dev/* /nix/store/hdw5358bda0b7g6f8xja7yvdjs3zl4wh-site-fs-0.0.1-dev/pr/12/final_final2/"

          cmds_list = let
            # Deployment command is different for copies vs symlinks
            cmd = ''${if symlink then "lndir -silent" else "cp -R"}'';
            # Whether a path ends in "", "/" or "/*" is different for above commands
            path_specifier = ''${if symlink then "" else "/*"}'';
          in builtins.map
            (
              elem: let
                drv = builtins.elemAt elem 0;
                p = "$out/" + path + "/" + (builtins.elemAt elem 1);
              in "${cmd} ${drv}${path_specifier} ${p}"
            )
            cmp;
          # deploy_cmds = pkgs.writeText "deploy_cmds.sh" (pkgs.lib.concatStringsSep "\n" cmds_list);
          deploy_cmds = pkgs.lib.concatStringsSep "\n" cmds_list;

          ### Assemble the commands to remove the blacklisted dirs
          ########################################################

          # e.g.
          # symlink=true  : rm -rf /nix/store/3dydb0fk2lsfzfbjvzq9hwsfvilsz2kc-ot-doxygen-0.0.1-dev/api-xml/
          # symlink=false :

          # Create a single list of l2-lists, each of which is the derivation + the dir from it to remove
          blist_cmds_list = with builtins; let
            list_of_all_pairs_for_one_drv = innerList : (let
              drv = elemAt innerList 0;
              dirs = elemAt innerList 1;
            in
              map ( x: [ drv x ] ) dirs
            );
          in concatLists (map (drv_2list: (list_of_all_pairs_for_one_drv drv_2list)) blacklist_dirs);

          # Create a string of all the fully-formed removal commands
          blist_cmds = with builtins; with pkgs.lib; let
          in concatStringsSep "\n"
            (
              forEach blist_cmds_list # forEach == map w. args reversed
                (x: let
                  drv = elemAt x 0;
                  # Find the matching path fs offset from the 'cmp' lists.
                  path_fs_offset = elemAt (findFirst (x: (elemAt x 0) == drv) [] cmp) 1;
                  path_frag = elemAt x 1;
                  dir = "$out/${path}/${path_fs_offset}${path_frag}";
                in ''
                  chmod +rwx ${dir}
                  rm -rf ${dir}
                ''
                )
            );


        in pkgs.stdenv.mkDerivation rec {
          pname = "site-fs";
          version = "0.0.1-dev";
          dontUnpack = true;
          content_root = "$out/${path}";
          nativeBuildInputs = [ landing book doxygen pkgs.outils ];
          buildPhase = ''
            for f in ${content_root}{/,/book,/gen/doxy}; do
              mkdir -p $f
            done

            # Run the deployment commands
            ${deploy_cmds}

            # Delete/Unlink blacklisted files or directories
            ${blist_cmds}
          '';
          dontInstall = true;
          dontFixup = true;
        };


        ###################################################
        ### Build the site filesystem for a specific URL ##
        ###################################################

        ot-site = {
          # Generalized schema for a URL
          # https://datatracker.ietf.org/doc/html/rfc1808.html#section-2.1
          # URL     == <scheme>://<net_loc>/<path>;<params>?<query>#<fragment>
          # net_loc is a sub-component of the URL schema ("network location and login information")
          # https://datatracker.ietf.org/doc/html/rfc1738#section-3.1
          # net_loc == <user>:<password>@<host>:<port>
          scheme ? "http",
          host ? "localhost",
          port ? "12321",
          path ? "pr/12/final_final2",
        }: rec {
          # Set a default port = 9000 with localhost
          # > We need a non-root port (>1024) to serve on localhost successfully
          # > (without an unnecessary escalation of privileges).
          serve-port =
            if (port != "")
            then "${port}"
            else "9000";

          baseURL = "${scheme}://${host}:${serve-port}";
          contentURL = "${scheme}://${host}:${serve-port}/${path}";

          # Built and assemble the site components with this baseURL+path
          #     baseURL -> Inserted into generated content to form links
          #     path    -> Used to assemble a filesystem suitable for hosting
          # The builder will combine baseURL/path to form a final URL for the content root.
          # (keep 'path' seperate to avoid re-parsing the URL)
          fs = site-fs {inherit baseURL path;};
        };

        ######################################################################
        ### Build a container image based upon the filesystem in 'ot-site' ###
        ######################################################################

        ot-site-image = let
          site = ot-site {
            scheme = "http";
            host = "localhost";
            port = "12321";
            path = "pr/12/final_final2";
          };
          fs = site.fs {symlink = false;};
          # in pkgs.dockerTools.buildLayeredImage rec {
          #   name = "site_image"; tag = "latest";
          #   contents = [ fs ];
          #   config.Cmd = ["${pkgs.python3}/bin/python" "-m" "http.server" "-d" "/" "${site.serve-port}"];
          #   maxLayers = 100;
          # };
        in
          pkgs.dockerTools.buildImage rec {
            name = "site_image";
            tag = "latest";
            created = "now"; # BREAKS BINARY REPRODUCIBILITY
            copyToRoot = pkgs.buildEnv {
              name = "image-root";
              paths = [fs];
            };
            config.Cmd = ["${pkgs.python3}/bin/python" "-m" "http.server" "-d" "/" "${site.serve-port}"];
          };
      in {
        packages = {
          landing = ot-landing {};
          book = ot-book {};
          doxygen = ot-doxygen {};
          site = (ot-site {}).fs {};
          site-image = ot-site-image;
          # A nice way to visually-examine the site's build-time dependencies:
          # https://github.com/utdemir/nix-tree
          # e.g.
          # $ nix run nixpkgs#nix-tree -- ./util/site#site --derivation
        };

        apps.serve = let
          site = ot-site {
            scheme = "http";
            host = "localhost";
            port = "";
            path = "";
          };
          fs = site.fs {symlink = true;};

          script = pkgs.writeShellScriptBin "serve" ''
            this_dir=$( cd -- "$( dirname -- "$BASH_SOURCE[0]" )" &> /dev/null && pwd )
            echo "----------------------------------------------------------------------------"
            echo "Script   : $this_dir/serve"
            echo "Root_Dir : ${fs}"
            echo ""
            echo "URL"
            echo "---> ${site.contentURL} <---"
            echo ""
            echo "----------------------------------------------------------------------------"
            ${pkgs.python3}/bin/python -m http.server -d ${fs} ${site.serve-port}
          '';
        in {
          type = "app";
          program = "${script}/bin/serve";
        };

        devShells.default = pkgs.mkShellNoCC rec {
          packages =
            (with pkgs; [
              hugo
              mdbook
              libxslt
              doxygen
              git
              mdbook
            ])
            ++ [
              my_pythonenv
            ];
          shellHook = ''
            helpstr=$(cat <<'EOF'
            > OpenTitan util/site shell environment.
            BROKEN, DO NOT RUN THESE SCRIPTS HERE.
            ./util/site/build-docs.sh serve          - Build and serve the website on localhost
            ./util/site/deploy.sh staging            - Build and deploy the site to staging.opentitan.org

            Type 'h' to see this message again.
            EOF
            )
            h(){ echo "$helpstr"; }
            h
          '';
        };

        formatter = inputs.nixpkgs.legacyPackages.${system}.alejandra;
      }
    );
}
