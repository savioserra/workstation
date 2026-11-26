# The go member: the mise-pinned toolchain and its editor profile entry.
{ wsLib, ... }:
{
  flake.modules.homeManager.languages =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      lang = wsLib.language { inherit config lib pkgs; };
    in
    lang.language [ "languages" "go" ] {
      description = "the go toolchain and its editor profile";
      tools.go = "1.27.3";
      editor = {
        requires = [ "go" ];
        extras = [ "lang.go" ];
        plugin = ./files/languages/plugins/go.lua;
      };
    };
}
