# The machine files: `local` is the flake's machine-files input
# (hosts/template in the tree, hosts/local through the override); the
# template machines drive the check legs, one per platform.
{ inputs, lib, ... }:
let
  machineOf = args: import ../lib/machine.nix ({ inherit lib; } // args);
in
{
  options.workstation.machines = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    description = "Machines by role, each the machine.nix view: identity, keys, homeModules.";
  };

  config.workstation.machines = {
    local = machineOf { root = inputs.machine-files; };
    template = machineOf { root = ../../hosts/template; };
    template-darwin = machineOf {
      root = ../../hosts/template;
      overrides.system = "aarch64-darwin";
    };
  };
}
