# The network domain's system plane (NixOS, nix-darwin): services.tailscale,
# following the operator home's workstation.network.enable.
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
}
