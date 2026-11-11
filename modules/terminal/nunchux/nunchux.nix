# The nunchux member (linux): the pinned checkout with its .platform marker
# and the theme-rendered launcher config.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../../nix/lib/capability.nix { inherit config lib pkgs; };
  theme = config.workstation.theme.lib;

  nunchuxTree =
    ws.overlayTree
      (pkgs.fetchFromGitHub {
        owner = "datamadsen";
        repo = "nunchux";
        rev = "1546eaa980d834c331496ea9d51942be07ea9fdd";
        hash = "sha256-C7sXigf8qB5umoZSU8nsqj6vPdd8NMhmTg8B64rysUw=";
      })
      [
        {
          path = "bin/.platform";
          source = ./files/.tmux/plugins/nunchux/bin/.platform;
        }
      ];

  nunchuxConfig = theme.assertNoUnresolved (
    theme.renderSlots (builtins.readFile ./files/.config/nunchux/config)
  );
in
ws.capability [ "terminal" "nunchux" ] {
  description = "the nunchux launcher (linux)";
  default = pkgs.stdenv.hostPlatform.isLinux;
  enable.defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
  config = {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "workstation.terminal.nunchux is linux-only";
      }
    ];
    home.packages = [ pkgs.fzf ];
    home.file = {
      ".tmux/plugins/nunchux".source = nunchuxTree;
      ".config/nunchux/config".text = nunchuxConfig;
    };
  };
}
