# The typescript member: the mise-pinned pnpm and its editor profile entry.
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
    lang.language [ "languages" "typescript" ] {
      description = "pnpm and the typescript editor profile";
      tools.pnpm = "12.9.0";
      editor = {
        requires = [ "node" ];
        extras = [
          "lang.typescript"
          "linting.eslint"
          "formatting.prettier"
        ];
        plugin = ./files/languages/plugins/typescript.lua;
      };
    };
}
