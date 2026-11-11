# The go member: the toolchain and its editor profile entry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../../nix/lib/capability.nix { inherit config lib pkgs; };
in
ws.capability [ "languages" "go" ] {
  description = "the go toolchain and its editor profile";
  config = {
    home.packages = [ pkgs.go ];
    workstation.editor = ws.whenOn "editor" {
      languages = [
        {
          id = "go";
          requires = [ "go" ];
          lazyvim_extras = [ "lazyvim.plugins.extras.lang.go" ];
          plugin_module = "languages.plugins.go";
        }
      ];
      languagePlugins = [ ./files/languages/plugins/go.lua ];
    };
  };
}
