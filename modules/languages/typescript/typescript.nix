# The typescript member: the mise-pinned pnpm and its editor profile entry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  lang = import ../../../nix/lib/language.nix { inherit config lib pkgs; };
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
    mason = [
      "typescript-language-server"
      "eslint-lsp"
      "prettier"
    ];
    plugin = ./files/languages/plugins/typescript.lua;
  };
}
