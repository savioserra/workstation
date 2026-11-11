# The network domain: tailscale. Standalone linux runs the substrate's
# tailscaled unit (files/tailscaled-ensure.sh); NixOS and darwin run
# services.tailscale.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
  on = config.workstation.network.enable;
  ensure = ws.script {
    name = "workstation-tailscaled";
    inputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnugrep
    ];
    prelude = "TAILSCALE_PKG=${pkgs.tailscale}\n";
    file = ./files/tailscaled-ensure.sh;
  };
in
{
  options.workstation.network.enable = lib.mkEnableOption "tailscale, the fleet transport";

  config = lib.mkMerge [
    (lib.mkIf (on && pkgs.stdenv.hostPlatform.isLinux) {
      home.packages = [ pkgs.tailscale ];
    })
    (lib.mkIf on {
      workstation.terminal.nunchux = ws.whenOn [ "terminal" "nunchux" ] {
        entries."app:net" = {
          cmd = "sh -c 'tailscale status | less -R'";
          desc = "Tailnet status";
          rank = 30;
        };
      };
    })
    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      home.activation.ensure-tailscaled = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${ensure}/bin/workstation-tailscaled ${if on then "on" else "off"} || true
      '';
    })
  ];
}
