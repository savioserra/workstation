# The tmux member: .tmux.conf, the pinned plugin checkouts and the reply
# drain function in bash and zsh.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../../nix/lib/capability.nix { inherit config lib pkgs; };

  drain = ''
    tmux() {
      command tmux "$@"
      local _rc=$?
      read -t 0.5 -r _ </dev/tty 2>/dev/null
      return $_rc
    }
  '';

  plugins = builtins.mapAttrs (_: pkgs.fetchFromGitHub) {
    "tpm" = {
      owner = "tmux-plugins";
      repo = "tpm";
      rev = "e261deb1b47614eed3400089ce7197dc68acc4eb";
      hash = "sha256-oRKUZNyJYQXlkeQfbEYiltUEBpvdwn2SoEBWHVUNmrA=";
    };
    "tmux2k" = {
      owner = "2KAbhishek";
      repo = "tmux2k";
      rev = "d8c5c2924c557835f984dd44eb71315b897bc4f5";
      hash = "sha256-++FpnS/N9OHGhWjnD/Q0Dhwd+S3wNRr7R9ArZKBwpwA=";
    };
    "tmux-yank" = {
      owner = "tmux-plugins";
      repo = "tmux-yank";
      rev = "acfd36e4fcba99f8310a7dfb432111c242fe7392";
      hash = "sha256-/5HPaoOx2U2d8lZZJo5dKmemu6hKgHJYq23hxkddXpA=";
    };
    "tmux-resurrect" = {
      owner = "tmux-plugins";
      repo = "tmux-resurrect";
      rev = "cff343cf9e81983d3da0c8562b01616f12e8d548";
      hash = "sha256-FcSjYyWjXM1B+WmiK2bqUNJYtH7sJBUsY2IjSur5TjY=";
    };
    "vim-tmux-navigator" = {
      owner = "christoomey";
      repo = "vim-tmux-navigator";
      rev = "e41c431a0c7b7388ae7ba341f01a0d217eb3a432";
      hash = "sha256-efqiRffnidYx+qjgsHyWshCFWgZp/ZrHl+Clt04pfpM=";
    };
  };
  # the running server keeps serving after a switch moved the generation's
  # binary (a switch never restarts it): report the skew, never restart —
  # the server holds live sessions and the restart stays the operator's
  skewRoutine = {
    name = "tmux-server-skew";
    text = ''
      srv_pid=$(ps -eo pid,comm | awk '$0 ~ /tmux: server/ {print $1; exit}')
      if [ -n "$srv_pid" ]; then
        srv_exe=$(readlink "/proc/$srv_pid/exe" 2>/dev/null || ps -o command= -p "$srv_pid" | awk '{print $1}')
        srv_ver=$(tmux display -p '#{version}' 2>/dev/null || echo '?')
        gen_ver=$(tmux -V 2>/dev/null || echo '?')
        gen_ver="''${gen_ver#tmux }"
        if [ "$srv_ver" = "$gen_ver" ]; then
          echo "workstation: tmux server check — current ($srv_ver at $srv_exe)"
        else
          echo "workstation: tmux server check — skew: running $srv_ver at $srv_exe, generation $gen_ver; your restart (the server holds live sessions)" >&2
        fi
      else
        echo "workstation: tmux server check — none running"
      fi
    '';
  };
in
ws.capability [ "terminal" "tmux" ] {
  description = "the tmux config and plugin set";
  default = true;
  config = lib.mkMerge [
    (ws.shellInit drain)
    {
      workstation.routines = {
        after-apply = [ skewRoutine ];
        after-rollback = [ skewRoutine ];
        after-update = [ skewRoutine ];
      };
    }
    {
      workstation.theme = ws.whenOn "theme" {
        consumers.tmux = {
          file = "tmux.conf";
          render =
            t:
            let
              p = t.palette;
              light = t.appearance == "light";
              canvas = if light then p.bg else "default";
              ink = if light then p.text else "default";
              # the theme's terminal colors in panes, or the terminal's own
              ansi =
                if t.ansi == null then
                  "set -gwu pane-colours\n"
                else
                  lib.concatStrings (lib.imap0 (i: c: "set -gw pane-colours[${toString i}] '${c}'\n") t.ansi);
            in
            ''
              set -g window-style 'fg=${ink},bg=${canvas}'
              set -g window-active-style 'fg=${ink},bg=${canvas}'
              set -g popup-style 'fg=${ink},bg=${canvas}'
              set -g popup-border-style 'fg=${p.chrome},bg=${canvas}'
              set -g menu-style 'fg=${ink},bg=${canvas}'
              set -g menu-selected-style 'fg=${p.selected_fg},bg=${p.selected_bg}'
              set -g menu-border-style 'fg=${p.chrome},bg=${canvas}'
              ${ansi}set -g @tmux2k-bg-main '${canvas}'
              set -g @tmux2k-bg-alt '${canvas}'
              set -g @tmux2k-dark-blue '${canvas}'
              set -g @tmux2k-black '${p.bg}'
              set -g @tmux2k-text '${p.bg}'
              set -g @tmux2k-white '${p.inactive}'
              set -g @tmux2k-gray '${p.chrome}'
              set -g @tmux2k-dark-gray '${p.chrome}'
              set -g @tmux2k-blue '${p.accent}'
              set -g @tmux2k-light-blue '${p.accent}'
              set -g @tmux2k-green '${p.ok}'
              set -g @tmux2k-light-green '${p.ok}'
              set -g @tmux2k-yellow '${p.warn}'
              set -g @tmux2k-light-yellow '${p.warn}'
              set -g @tmux2k-red '${p.err}'
              set -g @tmux2k-light-red '${p.err}'
              set -g @tmux2k-purple '${p.shortcut}'
              set -g @tmux2k-light-purple '${p.shortcut}'
              set -g @tmux2k-message-bg '${p.accent}'
              set -g @tmux2k-message-fg '${p.bg}'
              set -g @tmux2k-pane-border '${p.chrome}'
              set -g @tmux2k-pane-active-border '${p.accent}'
            '';
          # tmux with stdin off the tty: no terminfo load for $TERM, which the
          # darwin activation sets to unknown
          reload = ''
            if ${pkgs.tmux}/bin/tmux has-session </dev/null 2>/dev/null; then
              ${pkgs.tmux}/bin/tmux source-file "$STATE/current/tmux.conf" </dev/null 2>/dev/null || true
              ${pkgs.tmux}/bin/tmux run-shell -b "$HOME/.tmux/plugins/tmux2k/2k.tmux" </dev/null 2>/dev/null || true
            fi
          '';
        };
      };
    }
    {
      home.packages = [ pkgs.tmux ];
      home.file = lib.mkMerge (
        [
          {
            ".tmux.conf".source = ./files/.tmux.conf;
            ".config/tmux/tmux.conf".source =
              config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.tmux.conf";
          }
        ]
        ++ lib.mapAttrsToList (name: tree: { ".tmux/plugins/${name}".source = tree; }) plugins
      );
    }
  ];
}
