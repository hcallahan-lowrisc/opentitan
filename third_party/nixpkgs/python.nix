# https://github.com/charlottia/hdx/pull/1
inputs@{...}:
let
  python = (inputs.python.override {
    includeSiteCustomize = false;
  }).overrideAttrs (f: p: {
    postInstall = p.postInstall + ''
      # Override sitecustomize.py with our NIX_PYTHONPATH-preserving variant.
      cp ${./sitecustomize.py} $out/${f.passthru.sitePackages}/sitecustomize.py
    '';
  });
in
  python.override { self = python; }
