# Payload helpers, free of the module system: scripts and overlaid trees.
{ lib, pkgs }:
{
  # script: a payload file as a program on PATH; the payload sets its own
  # shell options
  script =
    {
      name,
      file,
      inputs ? [ ],
      prelude ? "",
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = inputs;
      bashOptions = [ ];
      text = prelude + builtins.readFile file;
    };

  # overlayTree base [ { path; source; } ]: base with each child laid at its
  # relative path
  overlayTree =
    base: children:
    let
      relative =
        c:
        lib.assertMsg (
          !(lib.hasPrefix "/" c.path) && !(builtins.elem ".." (lib.splitString "/" c.path))
        ) "overlayTree: the child path \"${c.path}\" must stay inside the tree";
    in
    if children == [ ] then
      base
    else
      assert lib.all relative children;
      pkgs.runCommand "ws-composed-${base.name or "tree"}" { } ''
        set -euo pipefail
        mkdir -p "$out"
        cp -a ${base}/. "$out/"
        chmod -R u+w "$out"
        ${lib.concatStrings (
          map (c: ''
            mkdir -p "$out/$(dirname "${c.path}")"
            if [ -d "${c.source}" ]; then
              mkdir -p "$out/${c.path}"
              cp -a "${c.source}"/. "$out/${c.path}"/
            else
              cp -a "${c.source}" "$out/${c.path}"
            fi
          '') children
        )}
      '';
}
