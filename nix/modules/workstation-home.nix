# The home plane core: the machine options, the workstation launcher and the
# switch driver (its routines: nix/modules/routines-home.nix).
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.workstation = {
    machine = {
      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The machine's captured host name (machine.json).";
      };
      checkout = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The workstation checkout: the launcher's flake outside a checkout (machine.json).";
      };
      vault = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The machine's 1Password vault (machine.json).";
      };
    };
    switch = {
      homeAttr = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The flake attr of this host's homeConfiguration: the switch driver's home-plane target.";
      };
      systemAttr = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The flake attr of this host's system configuration: the switch driver's --system target.";
      };
    };
  };

  config = {
    home.packages = [
      (pkgs.writeShellScriptBin "workstation" (
        "WORKSTATION_JQ=\${WORKSTATION_JQ:-${pkgs.jq}/bin/jq}\n"
        + lib.optionalString (
          config.workstation.machine.checkout != null
        ) "WORKSTATION_CHECKOUT=\${WORKSTATION_CHECKOUT:-${config.workstation.machine.checkout}}\n"
        + builtins.readFile ../../bin/workstation
      ))
      (import ../lib/switch.nix {
        inherit lib pkgs;
        homeAttr = config.workstation.switch.homeAttr;
        systemAttr = config.workstation.switch.systemAttr;
        routines = config.workstation.switch.routines;
      })
    ];

    home.stateVersion = lib.mkDefault "25.05";
    home.backupFileExtension = "hm-backup";
  };
}
