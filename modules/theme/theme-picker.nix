# The theme pick: the rendered theme tree (a dir per theme: tokens.json and
# each consumer's file) and the `workstation theme` program, seeded at apply.
{ wsLib, ... }:
{
  flake.modules.homeManager.theme =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };
      cfg = config.workstation.theme;
      home = config.home.homeDirectory;

      themeTree = pkgs.linkFarm "workstation-themes" (
        lib.concatLists (
          lib.mapAttrsToList (
            name: tokens:
            [
              {
                name = "${name}/tokens.json";
                path = pkgs.writeText "workstation-theme-${name}.json" (builtins.toJSON tokens);
              }
            ]
            ++ lib.mapAttrsToList (consumer: c: {
              name = "${name}/${c.file}";
              path = pkgs.writeText "workstation-theme-${name}-${consumer}" (c.render tokens);
            }) (lib.filterAttrs (_: c: c.file != null) cfg.consumers)
          ) cfg.tokens
        )
      );

      program = ws.script {
        name = "workstation-theme";
        inputs = [ pkgs.coreutils ];
        prelude = ''
          THEMES=${home}/.local/share/workstation/themes
          STATE=${home}/.local/state/workstation/theme
          DEFAULT=${cfg.default}
          reload_consumers() {
          THEME=$(picked) || return 0
          ${lib.concatMapStrings (c: c.reload) (builtins.attrValues cfg.consumers)}:
          :
          }
        '';
        file = ./files/workstation-theme.sh;
      };
    in
    {
      config = ws.whenOn "theme" {
        home.packages = [ program ];
        # the theme tree and the consumer links: the state path belongs to
        # the theme domain
        home.file = lib.mkMerge [
          { ".local/share/workstation/themes".source = themeTree; }
          (lib.mapAttrs' (
            name: c:
            lib.nameValuePair c.target {
              source = config.lib.file.mkOutOfStoreSymlink "${home}/.local/state/workstation/theme/current/${c.file}";
            }
          ) (lib.filterAttrs (_: c: c.target != null && c.file != null) cfg.consumers))
        ];
        home.activation.workstation-theme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          ${program}/bin/workstation-theme seed || true
          ${lib.concatMapStrings (c: c.activate) (builtins.attrValues cfg.consumers)}
        '';
      };
    };
}
