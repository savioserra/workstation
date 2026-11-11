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
      languages = [
        {
          id = "typescript";
          requires = [ "node" ];
          lazyvim_extras = [
            "lazyvim.plugins.extras.lang.typescript"
            "lazyvim.plugins.extras.linting.eslint"
            "lazyvim.plugins.extras.formatting.prettier"
          ];
          mason_packages = [
            "typescript-language-server"
            "eslint-lsp"
            "prettier"
          ];
          plugin_module = "languages.plugins.typescript";
        }
      ];
      languagePlugins = [ ./files/languages/plugins/typescript.lua ];
    };
  };
}
