# Capability helpers: the enable option and its gate, guarded contributions,
# the theme tokens, bash+zsh init; the payload helpers ride along.
{
  lib,
  pkgs,
  config,
}:
let
  # isOn [ "languages" "go" ]: every enable on the path holds; an
  # undeclared path fails the eval
  isOn =
    path:
    lib.all (n: lib.getAttrFromPath ([ "workstation" ] ++ lib.take n path ++ [ "enable" ]) config) (
      lib.range 1 (builtins.length path)
    );
in
import ./payload.nix { inherit lib pkgs; }
// {
  inherit isOn;

  # capability [ "languages" "go" ] { description; default?; enable?; imports?; options?; config?; }
  # a path is <domain> or <domain>/<member>, the grammar of the selection verbs
  capability =
    path: spec:
    assert lib.assertMsg (builtins.elem (builtins.length path) [
      1
      2
    ]) "capability: the path ${lib.concatStringsSep "/" path} must be <domain> or <domain>/<member>";
    {
      imports = spec.imports or [ ];
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
      config = lib.mkIf (isOn path) (spec.config or { });
    };

  # whenOn "editor" | whenOn [ "languages" "go" ]: a contribution guarded
  # by every enable on the owner's path; an undeclared owner fails the eval
  whenOn = owner: lib.mkIf (isOn (lib.toList owner));

  # themeTokens: the color map tokens per theme,
  # { <theme> = { name; appearance; palette; ansi; }; }; a capability maps
  # them into its own setup; empty without the theme domain
  themeTokens = lib.attrByPath [ "workstation" "theme" "tokens" ] { } config;

  shellInit = text: {
    programs.bash.initExtra = text;
    programs.zsh.initContent = text;
  };
}
