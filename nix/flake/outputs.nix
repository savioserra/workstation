# The machine's outputs: its legs (home + NixOS on linux, darwin on a mac)
# and `workstation` — the read verbs' report, the applied rev, the leg keys.
{
  config,
  lib,
  self,
  ...
}:
let
  machine = config.workstation.machines.local;
  legs = config.workstation.legs;
  machineHome = legs.home machine.system machine.homeModules;
in
{
  options.flake.workstation = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    description = "The launcher's read surface: report (the read verbs), rev, keys (the switch targets).";
  };

  config.flake = {
    workstation = {
      report = import ../report.nix {
        inherit lib;
        eval = machineHome;
        root = self;
        inherit (machine) settings;
      };
      rev = self.rev or self.dirtyRev or "unknown";
      keys = {
        home = machine.homeKey;
        system = machine.systemKey;
      };
    };

    homeConfigurations = lib.optionalAttrs (!machine.isDarwin) {
      ${machine.homeKey} = machineHome;
    };
    nixosConfigurations = lib.optionalAttrs (!machine.isDarwin) {
      ${machine.systemKey} = legs.linux machine;
    };
    darwinConfigurations = lib.optionalAttrs machine.isDarwin {
      ${machine.systemKey} = legs.mac machine;
    };
  };
}
