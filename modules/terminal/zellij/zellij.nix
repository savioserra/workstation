# The zellij member: the multiplexer through home-manager's programs.zellij,
# sessions serialized for resurrection, the pane viewport kept off disk, the
# unlock-first keybinds, the theme and the pane frames.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../../nix/lib/capability.nix { inherit config lib pkgs; };
in
ws.capability [ "terminal" "zellij" ] {
  description = "the zellij multiplexer with session resurrection";
  default = true;
  config = {
    programs.zellij = {
      enable = true;
      settings = {
        # every session serialized to the cache dir: resurrectable after a
        # quit, a crash or a reboot
        session_serialization = true;
        # pane contents stay off disk: no secrets in the serialized state
        serialize_pane_viewport = false;
        # the built-in non-colliding preset: locked by default, Ctrl g
        # unlocks, then single keys enter the modes
        keybinds._props.preset = "unlock-first";
        theme = "dracula";
        theme_dark = "default";
        show_startup_tips = false;
        ui.pane_frames = {
          rounded_corners = true;
          hide_session_name = true;
        };
      };
    };
  };
}
