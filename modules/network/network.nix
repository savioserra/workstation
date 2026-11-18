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
  report = ws.script {
    name = "tailscale-report";
    inputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.jq
      pkgs.tailscale
    ];
    file = ./files/tailscale-report;
  };
in
{
  options.workstation.network.enable = lib.mkEnableOption "tailscale, the fleet transport";

  config = lib.mkMerge [
    (lib.mkIf (on && pkgs.stdenv.hostPlatform.isLinux) {
      home.packages = [
        pkgs.tailscale
        report
      ];
    })
    (lib.mkIf on {
      workstation.terminal.nunchux = ws.whenOn [ "terminal" "nunchux" ] {
        entries."menu:network" = {
          desc = "Network";
          rank = 30;
        };
        entries."app:network/tailscale" = {
          cmd = "tailscale-report view | less -R";
          desc = "Tailnet status";
          # the popup sizes itself to the rendered report (`!command` dims)
          width = "!tailscale-report width";
          height = "!tailscale-report height";
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
