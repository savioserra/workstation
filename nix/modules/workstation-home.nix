# The home plane: the capability modules, the workstation launcher and the
# switch driver.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  routine = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "A store-name-safe routine id (kebab-case).";
      };
      text = lib.mkOption {
        type = lib.types.lines;
        description = "The routine body: a shell fragment run by the switch driver at the owning event.";
      };
    };
  };
in
{
  imports = [ ../../modules ];

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
      peers = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "The machine's A2A peers (peers.nix).";
      };
    };
    routines = {
      after-apply = lib.mkOption {
        type = lib.types.listOf routine;
        default = [ ];
        description = "Routines the switch driver runs after a successful apply (either plane), after the receipt; a failed routine reports and never fails the switch.";
      };
      after-rollback = lib.mkOption {
        type = lib.types.listOf routine;
        default = [ ];
        description = "Routines the switch driver runs after a rollback's activation.";
      };
      after-update = lib.mkOption {
        type = lib.types.listOf routine;
        default = [ ];
        description = "Routines the switch driver runs after a flake.lock update.";
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
        routines = config.workstation.routines;
      })
    ];

    home.stateVersion = "25.05";
    home.backupFileExtension = "hm-backup";
  };
}
