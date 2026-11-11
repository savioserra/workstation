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
      languages.go = {
        requires = [ "go" ];
        extras = [ "lang.go" ];
        plugin = ./files/languages/plugins/go.lua;
      };
    };
  };
}
