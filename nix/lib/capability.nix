# Capability helpers: the enable option and its gate, guarded contributions,
# bash+zsh init, payload scripts, overlaid trees.
{
  lib,
  pkgs,
  config ? null,
}:
let
  enabledOr =
    fallback: path: lib.attrByPath ([ "workstation" ] ++ path ++ [ "enable" ]) fallback config;
  chain = path: lib.all (n: enabledOr true (lib.take n path)) (lib.range 1 (builtins.length path));
in
{
  # capability [ "languages" "go" ] { description; default?; enable?; options?; config?; }
  capability = path: spec: {
    options.workstation = lib.setAttrByPath path (
      {
        enable =
          lib.mkEnableOption spec.description
          // {
            default = spec.default or false;
          }
          // (spec.enable or { });
      }
      // (spec.options or { })
    );
    config = lib.mkIf (chain path) (spec.config or { });
  };

  # whenOn "editor" { … }: a contribution guarded by the owning domain's enable
  whenOn = domain: lib.mkIf (lib.getAttrFromPath [ "workstation" domain "enable" ] config);

  shellInit = text: {
    programs.bash.initExtra = text;
    programs.zsh.initContent = text;
  };

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

  overlayTree =
    base: children:
    if children == [ ] then
      base
    else
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
