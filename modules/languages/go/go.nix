# The go member: the mise-pinned toolchain and its editor profile entry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  lang = import ../../../nix/lib/language.nix { inherit config lib pkgs; };
in
lang.language [ "languages" "go" ] {
  description = "the go toolchain and its editor profile";
  tools.go = "1.27.3";
  editor = {
    requires = [ "go" ];
    extras = [ "lang.go" ];
    plugin = ./files/languages/plugins/go.lua;
  };
}
