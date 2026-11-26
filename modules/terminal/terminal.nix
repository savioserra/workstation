# The terminal domain: eza (ls), the starship prompt, btop and mosh.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };

  # the remote mosh-server under the home-manager session vars (the profile
  # PATH, LOCALE_ARCHIVE_2_27): an ssh command on a bash host sources none
  moshServer = lib.concatStrings [
    ''for f in "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"; do [ -r "$f" ] && . "$f"; done; ''
    ''PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH" mosh-server''
  ];
  mosh = lib.hiPrio (
    pkgs.writeShellScriptBin "mosh" ''
      for arg in "$@"; do
        case $arg in
        --server | --server=*) exec ${pkgs.mosh}/bin/mosh "$@" ;;
        esac
      done
      exec ${pkgs.mosh}/bin/mosh --server=${lib.escapeShellArg moshServer} "$@"
    ''
  );
in
ws.capability [ "terminal" ] {
  description = "eza, starship, mosh, btop and zellij";
  default = true;
  config = {
    home.packages = [
      pkgs.mosh
      mosh
      pkgs.btop
    ];
    programs.eza = {
      enable = true;
      icons = "auto";
      extraOptions = [ "--group-directories-first" ];
    };
    home.shellAliases.ls = "eza -lh";

    programs.starship.enable = true;
    xdg.configFile."starship.toml".source = ./starship.toml;

    workstation.theme = ws.whenOn "theme" {
      consumers.btop = {
        file = "btop.theme";
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

    home.file.".config/btop/themes/starlight.theme" =
      if config.workstation.theme.enable then
        {
          source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/workstation/theme/current/btop.theme";
        }
      else
        { enable = false; };

    # the pick owns the colors: btop reads the starlight theme file, the
    # symlink follows the pick; the rest of btop.conf stays user-owned
    home.activation.btop-theme = lib.mkIf config.workstation.theme.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ${config.home.homeDirectory}/.config/btop/themes
        if [ -f ${config.home.homeDirectory}/.config/btop/btop.conf ]; then
          ${pkgs.gnused}/bin/sed -i 's|^color_theme.*|color_theme = "starlight"|' ${config.home.homeDirectory}/.config/btop/btop.conf
        else
          printf 'color_theme = "starlight"\n' > ${config.home.homeDirectory}/.config/btop/btop.conf
        fi
      ''
    );
  };
}
