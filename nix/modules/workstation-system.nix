# The system plane on NixOS and nix-darwin: system packages.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.workstation;
in
{
  options.workstation = {
    enable = lib.mkEnableOption "the workstation substrate (the system plane of the nixpkgs-native monorepo)";

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional system packages for this host's workstation plane.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.btop
      pkgs.zellij
    ]
    ++ cfg.extraPackages;
  };
}
