# The system plane on NixOS and nix-darwin: system packages.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.workstation;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.tmux
          pkgs.btop
        ]
        ++ cfg.extraPackages;
      }
      (lib.mkIf (!isDarwin) {
        system.activationScripts.workstation = {
          deps = [ "users" ];
          text = ''
            echo "workstation: substrate staged (system plane)"
            echo "workstation: substrate staged (system plane)" > /dev/kmsg 2>/dev/null || true
          '';
        };
      })
    ]
  );
}
