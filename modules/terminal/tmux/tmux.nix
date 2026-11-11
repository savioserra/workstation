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
in
ws.capability [ "terminal" "tmux" ] {
  description = "the tmux config and plugin set";
  default = true;
  config = lib.mkMerge [
    (ws.shellInit drain)
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
