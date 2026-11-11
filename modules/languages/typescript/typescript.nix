# The typescript member: pnpm and its editor profile entry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../../nix/lib/capability.nix { inherit config lib pkgs; };
in
ws.capability [ "languages" "typescript" ] {
  description = "pnpm and the typescript editor profile";
  config = {
    home.packages = [ pkgs.pnpm ];
    workstation.editor = ws.whenOn "editor" {
      languages.typescript = {
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
    };
  };
}
