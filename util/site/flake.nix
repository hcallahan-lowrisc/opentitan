{
  description = "A flake for developing and building the OpenTitan site";

  # Set nix.conf for this flake
  nixConfig.bash-prompt = "\[opentitan-site\]$ ";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
  inputs.nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.nix-filter.url = "github:numtide/nix-filter";

  outputs = inputs @ { self, ... }:
    inputs.flake-utils.lib.eachSystem
      (with inputs.flake-utils.lib.system; [ x86_64-linux /* aarch64-darwin */ ])
      (system: let
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [ (import inputs.rust-overlay) ];
        };
        pkgs-unstable = import inputs.nixpkgs-unstable {
          inherit system;
        };

        proj_root = ./../..;

        my_pythonenv = pkgs.python3.withPackages (ps: with ps; [hjson Mako mistletoe pyyaml libcst tabulate semantic-version]);
        my_rustenv = { inherit (self.rust-bin.stable.latest) rustc cargo rustdoc rust-std; };

        # Some basic url/path sanitizers to try and stop shooting myself in the feet
        # e.g to avoid double-slashes when joining paths
        san = rec {
          nodelims = str: with builtins; let
            delims = [ ":" "/" ];
            cond =
              (str == "") || (
                ! elem (tail (pkgs.lib.stringToCharacters str)) delims &&
                ! elem (head (pkgs.lib.stringToCharacters str)) delims
              );
          in
            assert (pkgs.lib.assertMsg cond "String must not start/end with delimiters!");
            str;
        };

        #################################################################################
        ### Build the components of the site individually.                            ###
        # ot-doxygen : Doxygen-generated html docs for parts of the c/c++ sw codebase
        # ot-landing : Hugo static-site, the landing site for opentitan.org
        # ot-book    : mdBook build from all project markdown documentation
        #################################################################################

        ot-doxygen = pkgs.stdenv.mkDerivation {
          pname = "ot-doxygen";
          version = "0.0.1-dev";
          src = inputs.nix-filter.lib {
            root = proj_root;
            include = [ # If an 'include' attr is not passed, all paths are included.
              "util/doxygen/Doxyfile"
              "site/doxygen/"
              "sw/device/"
              "sw/ip/"
              "sw/lib/sw/device/base/freestanding/"
              "hw/top_earlgrey/sw/"
              "hw/top_darjeeling/sw/"
            ];
          };
          nativeBuildInputs = with pkgs; [doxygen];
          dontInstall = true;
          dontFixup = true;
          outputs = [
            "html" # The generated html files only
            "xml"  # The generated xml (used for some checking steps) # https://www.doxygen.nl/manual/customize.html#xmlgenerator
            "out"  # All remaining artifacts of build (e.g. logs)
          ];
          patchPhase = ''
            # Patch the doxyfile to:
            # - Build directly into our multiple-outputs
            # - Remove the git dependency from the Doxyfile by using the flake rev directly
            sed -e '/HTML_OUTPUT\s*=\s/         s|"\(.*\)"$|${placeholder "html"}      |' -i util/doxygen/Doxyfile
            sed -e '/XML_OUTPUT\s*=\s/          s|"\(.*\)"$|${placeholder "xml"}       |' -i util/doxygen/Doxyfile
            sed -e '/FILE_VERSION_FILTER\s*=\s/ s|"\(.*\)"$|echo ${self.rev or "dirty"}|' -i util/doxygen/Doxyfile
          '';
          buildPhase = ''
            doxygen_env="env"
            doxygen_env+=" SRCTREE_TOP=."
            doxygen_env+=" DOXYGEN_OUT=$out"
            doxygen_args="util/doxygen/Doxyfile"

            mkdir -p $out $html $xml
            $doxygen_env doxygen $doxygen_args
          '';
        };

        ot-landing = {
          baseURL
        }: pkgs.stdenv.mkDerivation {
          pname = "ot-landing";
          version = "0.0.1-dev";
          src = inputs.nix-filter.lib {
            root = proj_root;
            include = [ # If an 'include' attr is not passed, all paths are included.
              "site/landing/"
              "site/block-diagram/"
              "util/site-dashboard/"
              "util/site/blocks.json"
            ];
          };
          nativeBuildInputs = [pkgs.hugo];
          dontInstall = true;
          dontFixup = true;
          patchPhase = ''
            # Replace some relative symlinks with the real files, as Hugo seems to choke on these for some reason.
            replace_symlink() { cp --remove-destination $(readlink -f $1) $1; }
            for f in site/landing/static/js/{dashboard.js,ot-nightly-results.js}; do
              replace_symlink $f
            done
          '';
          buildPhase = ''
            hugo_args=""
            hugo_args+=" --source site/landing/"
            hugo_args+=" --destination $out"
            hugo_args+=" --baseURL ${baseURL}"

            mkdir $out
            hugo $hugo_args
          '';
        };

        ot-book = {
          baseURL,
          # We need the doxygen files plus the final URL where they will be hosted during the mdbook build, as
          # some markdown content is autogenerated from this information (e.g. links, summaries).
          doxyURL,
          doxyXML
        }: pkgs.stdenv.mkDerivation {
          pname = "ot-book";
          version = "0.0.1-dev";
          src = inputs.nix-filter.lib.filter {
            root = proj_root;
            exclude = [ # Pass everything except these items.
              "util/site/flake.nix"
              "util/site/flake.lock"
              "ci/"
              "quality/"
              "release/"
              "rules/"
              "third_party/"
              "sw/vendor/wycheproof/"
            ];
          };
          nativeBuildInputs = with pkgs; [mdbook libxslt] ++ [my_pythonenv];
          patchPhase = ''
            patchShebangs --build . &>/dev/null
          '';
          buildPhase = ''
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
            book_env+=" MDBOOK_PREPROCESSOR__BLOCK_DASHBOARD__COMMAND=util/mdbook-block-dashboard.py"
            book_env+=" MDBOOK_PREPROCESSOR__DOXYGEN__COMMAND=util/mdbook_doxygen.py"
            book_env+=" MDBOOK_PREPROCESSOR__DOXYGEN__XML_DIR=${doxyXML}"
            book_env+=" MDBOOK_PREPROCESSOR__DOXYGEN__HTML_URL=${doxyURL}"

            book_args="build"
            book_args+=" --dest-dir $out"

            mkdir -p $out
            $book_env mdbook $book_args
          '';
          dontInstall = true;
          dontFixup = true;
        };

        #######################################################
        ### Assemble components into a full site filesystem ###
        #######################################################

        ot-site-fs = {
          baseURL,
          path # (keep 'path' seperate to avoid re-parsing the URL)
        }: {
          symlink ? true
        }: let

          # The paths of some components are hardcoded here, as various parts of the sources
          # they themselves hardcode this expectation. It's probably not ever worth making
          # this a variable of the build.
          doxygen_path = "gen/doxy/"; # sw/README.md uses an absolute link to this path to hyperlink into to doxygen pages
          book_path    = "book/"; # Many href/absolute links expect the book at this path

          ### Create derivations specialized by the filesystem-mappings we want.
          # The values are the derivations themselves, while the keys are the locations
          # in the final filesystem where each derivation should be deployed to.
          fsmap = let self = {
            "" = ot-landing {
              baseURL = "${baseURL}";
            };
            "${doxygen_path}" = ot-doxygen;
            "${book_path}" = ot-book {
              baseURL = "${baseURL}/${book_path}";
              doxyURL = "${baseURL}/${doxygen_path}";
              doxyXML = self."${doxygen_path}".xml;
            };
          }; in self;

          ### Assemble the buildPhase copy/link commands ###
          # Support optionally constructing the site filesystem from symlinks instead of
          # direct copies of files, which can help to keep the build-time down.
          # The boolean input "symlink" is used to control this.
          # e.g.
          # symlink=true  : "lndir -silent <inputdrv>   <outputdrv>/pr/12/final_final2/"
          # symlink=false : "cp -R         <inputdrv>/* <outputdrv>/pr/12/final_final2/"

          deploy_cmds_list = let
            path' = san.nodelims path;
            cmd            = if symlink then "lndir -silent" else "cp -R";
            path_specifier = if symlink then ""              else "/*";
          in builtins.attrValues
            (builtins.mapAttrs
              (k: v: ''
                 mkdir -p $out/${path'}/${k}
                 ${cmd} ${v}${path_specifier} $out/${path'}/${k}
               '')
              fsmap
            );

        in pkgs.stdenv.mkDerivation {
          pname = "site-fs";
          version = "0.0.1-dev";
          dontUnpack = true;
          nativeBuildInputs = [ pkgs.outils /* contains 'lndir' */ ];
          buildPhase = ''
            mkdir -p $out
            # Run all the deployment commands
            ${pkgs.lib.concatStringsSep "\n" deploy_cmds_list}
          '';
          dontInstall = true;
          dontFixup = true;
        };


        ###################################################
        ### Build the site filesystem for a specific URL ##
        ###################################################

        # Borrow some argnames from the rfc1808 generalized schema for a URL
        # https://datatracker.ietf.org/doc/html/rfc1808.html#section-2.1
        # URL     == <scheme>://<net_loc>/<path>;<params>?<query>#<fragment>
        # net_loc is a sub-component of the URL schema ("network location and login information")
        # https://datatracker.ietf.org/doc/html/rfc1738#section-3.1
        # net_loc == <user>:<password>@<host>:<port>

        ot-site = {
          scheme, # e.g. "http"
          host,   # e.g. "localhost"
          port,   # e.g. "12321"
          path    # e.g. "my/subdir"
            #   'path' - Build for a subpath within the domain.
            #   (e.g. as an alternative to a URL-rewriting reverse-proxy)
            #   If path = my/subdir
            #   -> site root = http://localhost:12321/my/subdir/index.html
        }: let
          assemble_uri = {scheme, host, port ? "", path ? ""} : let
            port' = if (port == "") then ""
                    else ":" + (san.nodelims port);
            path' = if (path == "") then ""
                    else "/" + (san.nodelims path);
          in ''${scheme}://${host}${port'}${path'}'';

        in rec {
          baseURL = assemble_uri { inherit scheme host port path; };
          fs = ot-site-fs {inherit baseURL path;};
          inherit port;
        };

      in {
        packages = rec {
          # Some example arguemnts, just for debug builds
          landing = ot-landing {
            baseURL = "http://localhost:9000";
          };
          book = ot-book {
            baseURL = "http://localhost:9000";
            doxyURL = "http://localhost:9000/gen/doxy";
            doxyXML = doxygen.xml;
          };
          doxygen = ot-doxygen;
          fs = (
            ot-site {scheme = "http"; host = "localhost"; port = "12321"; path = "my/subdir";}
          ).fs {symlink = true;};
        };

        apps.serve = let
          site = ot-site {
            scheme = "http";
            host = "localhost";
            port = "9000";
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
            echo "---> ${site.baseURL} <---"
            echo ""
            echo "----------------------------------------------------------------------------"
            ${pkgs.python3}/bin/python -m http.server -d ${fs} ${site.port}
          '';
        in {
          type = "app";
          program = "${script}/bin/serve";
        };

        # To run a build using the devShell (+ existing scripts)
        # $ nix develop --command bash -c "./build-docs.sh serve"
        # OR
        # $ nix develop
        # $ ./build-docs.sh serve
        devShells.default = pkgs.mkShellNoCC rec {
          packages =
            (with pkgs; [ hugo mdbook libxslt doxygen git mdbook ]) ++
            (with pkgs-unstable; [ bazel ]) ++
            [ my_pythonenv ];
          USE_BAZEL_VERSION = "${pkgs-unstable.bazel.version}"; # 6.3.2-ish
          shellHook = ''
            helpstr=$(cat <<'EOF'
            > OpenTitan util/site shell environment.
            ./build-docs.sh serve          - Build and serve the website on localhost
            ./deploy.sh staging            - Build and deploy the site to staging.opentitan.org

            Type 'h' to see this message again.
            Type 'exit' to leave.
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
