# The editor domain: neovim and the language entries the members declare.
# | File | Owns |
# | --- | --- |
# | editor.nix | neovim, the language entry type, the editor variables |
# | editor-config.nix | the nvim config tree with the composed language profile, deployed writable and pruned by the managed list |
# | editor-lazy-lock.nix | the lazy-lock merge over the payload baseline |
{ wsLib, ... }:
{
  imports = [
    ./editor-config.nix
    ./editor-lazy-lock.nix
  ];

  flake.modules.homeManager.editor =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };
      nvim = pkgs.neovim;
    in
    ws.capability [ "editor" ] {
      description = "neovim and the composed language profile";
      default = true;
      options.languages = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              requires = lib.mkOption {
                type = lib.types.listOf lib.types.nonEmptyStr;
                default = [ ];
                description = "Host capability ids the entry needs (the profile's `requires`).";
              };
              extras = lib.mkOption {
                type = lib.types.listOf lib.types.nonEmptyStr;
                default = [ ];
                description = "LazyVim extras under lazyvim.plugins.extras (`lang.go`), imported before the base specs.";
              };
              mason = lib.mkOption {
                type = lib.types.listOf lib.types.nonEmptyStr;
                default = [ ];
                description = "Mason packages (each pinned in mason-lock.json).";
              };
              plugin = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "The lazy.nvim spec module, deployed as lua/languages/plugins/<id>.lua and imported after the base specs.";
              };
            };
          }
        );
        default = { };
        description = "Language entries keyed by profile id, composed into lua/languages/profile.lua.";
      };

      config = {
        home.packages = [ pkgs.tree-sitter ];

        home.sessionVariables = {
          EDITOR = "nvim";
          VISUAL = "nvim";
          GIT_EDITOR = "nvim";
        };

        home.file = {
          ".local/bin/nvim".source = "${nvim}/bin/nvim";
        };
      };
    };
}
