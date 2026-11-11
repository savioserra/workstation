# Capability helpers: the enable option and its gate, guarded contributions,
# the theme tokens, bash+zsh init, payload scripts, overlaid trees.
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

  # whenOn "editor" | whenOn [ "terminal" "nunchux" ]: a contribution guarded
  # by every enable on the owner's path; an undeclared owner fails the eval
  whenOn =
    owner:
    let
      path = lib.toList owner;
    in
    lib.mkIf (
      lib.all (n: lib.getAttrFromPath ([ "workstation" ] ++ lib.take n path ++ [ "enable" ]) config) (
        lib.range 1 (builtins.length path)
      )
    );

  # themeTokens: the color map tokens per theme,
  # { <theme> = { name; appearance; palette; ansi; }; }; a capability maps
  # them into its own setup; empty without the theme domain
  themeTokens = lib.attrByPath [ "workstation" "theme" "tokens" ] { } config;

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
