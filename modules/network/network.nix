# The network domain: tailscale. Standalone linux runs the substrate's
# tailscaled unit (files/tailscaled-ensure.sh); NixOS and darwin run
# services.tailscale, following the operator home's workstation.network.enable.
{ wsLib, ... }:
let
  systemPlane =
    { config, lib, ... }:
    let
      user = config.workstation.host.user;
    in
    {
      config =
        lib.mkIf
          (
            config.workstation.enable
            && user != null
            && config.home-manager.users.${user}.workstation.network.enable
          )
          {
            services.tailscale.enable = true;
          };
    };
in
{
  flake.modules.nixos.network = systemPlane;
  flake.modules.darwin.network = systemPlane;

  flake.modules.homeManager.network =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };
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
      options.workstation.network.enable = lib.mkEnableOption "tailscale";

      config = lib.mkMerge [
        (lib.mkIf (on && pkgs.stdenv.hostPlatform.isLinux) {
          home.packages = [
            pkgs.tailscale
            report
          ];
        })
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          home.activation.ensure-tailscaled = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            ${ensure}/bin/workstation-tailscaled ${if on then "on" else "off"} || true
          '';
        })
      ];
    };
}
