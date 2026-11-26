# A hermes skin per theme from the color map tokens; the pick's skin is
# set on change.
{ wsLib, ... }:
{
  flake.modules.homeManager.agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };
      launcher = "${config.programs.hermes.package}/hermes-launcher";

      hermesSkin =
        t:
        let
          p = t.palette;
        in
        {
          name = "workstation-${t.name}";
          description = "The workstation ${t.name} theme";
          colors = {
            background = p.bg;
            banner_title = p.accent;
            banner_accent = p.accent;
            banner_text = p.text;
            banner_dim = p.muted;
            banner_border = p.chrome;
            ui_accent = p.accent;
            ui_tool = p.shortcut;
            ui_label = p.shortcut;
            ui_text = p.text;
            ui_border = p.chrome;
            ui_ok = p.ok;
            ui_warn = p.warn;
            ui_error = p.err;
            prompt = p.text;
            input_rule = p.chrome;
            response_border = p.accent;
            session_label = p.shortcut;
            session_border = p.chrome;
            status_bar_bg = p.bg;
            status_bar_text = p.text;
            status_bar_strong = p.accent;
            status_bar_dim = p.muted;
            status_bar_good = p.ok;
            status_bar_warn = p.warn;
            status_bar_bad = p.err;
            status_bar_critical = p.err;
            completion_menu_bg = p.bg;
            completion_menu_current_bg = p.selected_bg;
            selection_bg = p.selected_bg;
            shell_dollar = p.accent;
            voice_status_bg = p.bg;
          };
        };

      skinFiles = lib.mapAttrs' (
        name: t:
        lib.nameValuePair ".hermes/skins/workstation-${name}.yaml" {
          source = (pkgs.formats.yaml { }).generate "hermes-skin-${name}.yaml" (hermesSkin t);
        }
      ) ws.themeTokens;
    in
    {
      config = ws.whenOn "agent" {
        home.file = ws.whenOn "theme" skinFiles;

        workstation.theme = ws.whenOn "theme" {
          consumers.hermes.reload = ''
            if [ "$(${launcher} config get display.skin </dev/null 2>/dev/null)" != "workstation-$THEME" ]; then
              ${launcher} config set display.skin "workstation-$THEME" </dev/null >/dev/null 2>&1 || true
            fi
          '';
        };
      };
    };
}
