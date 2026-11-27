# btop and its theme consumer: a btop.theme per theme, linked to the pick.
{ wsLib, ... }:
{
  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };
    in
    {
      config = ws.whenOn "terminal" {
        home.packages = [ pkgs.btop ];

        workstation.theme = ws.whenOn "theme" {
          consumers.btop = {
            file = "btop.theme";
            target = ".config/btop/themes/starlight.theme";
            # the pick owns the colors: btop reads the starlight theme file,
            # the link follows the pick; the rest of btop.conf stays
            # user-owned
            activate = ''
              mkdir -p ${config.home.homeDirectory}/.config/btop/themes
              if [ -f ${config.home.homeDirectory}/.config/btop/btop.conf ]; then
                ${pkgs.gnused}/bin/sed -i 's|^color_theme.*|color_theme = "starlight"|' ${config.home.homeDirectory}/.config/btop/btop.conf
              else
                printf 'color_theme = "starlight"\n' > ${config.home.homeDirectory}/.config/btop/btop.conf
              fi
            '';
            render =
              t:
              let
                p = t.palette;
                key = k: v: ''theme[${k}]="${v}"'';
                gradient =
                  k: a: b: c:
                  lib.concatStringsSep "\n" [
                    (key "${k}_start" a)
                    (key "${k}_mid" b)
                    (key "${k}_end" c)
                  ];
              in
              lib.concatStringsSep "\n" [
                (key "main_bg" p.bg)
                (key "main_fg" p.text)
                (key "title" p.accent)
                (key "hi_fg" p.shortcut)
                (key "selected_bg" p.selected_bg)
                (key "selected_fg" p.selected_fg)
                (key "inactive_fg" p.inactive)
                (key "graph_text" p.muted)
                (key "proc_misc" p.ok)
                (key "cpu_box" p.chrome)
                (key "mem_box" p.chrome)
                (key "net_box" p.chrome)
                (key "proc_box" p.chrome)
                (key "div_line" p.chrome)
                (gradient "temp" p.ramp_start p.ramp_mid p.ramp_end)
                (gradient "cpu" p.ramp_start p.ramp_mid p.ramp_end)
                (gradient "free" p.inactive "" p.ok)
                (gradient "cached" p.chrome "" p.accent)
                (gradient "available" p.warn "" p.accent)
                (gradient "used" p.err "" p.ramp_end)
                (gradient "download" p.muted p.chrome p.accent)
                (gradient "upload" p.err p.shortcut p.ramp_mid)
              ];
          };
        };

      };
    };
}
