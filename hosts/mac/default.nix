# The mac leg (nix-darwin): the host identity, Homebrew pinned by
# nix-homebrew and the machine's home plane through home-manager. Applied
# by nix/flake/legs.nix with importApply.
{
  machine,
  homePlane,
  ...
}:
{ config, lib, ... }:
{
  nixpkgs.hostPlatform = machine.system;
  nix.enable = false;
  nixpkgs.config.allowUnfreePredicate = import ../../nix/lib/license.nix { inherit lib; };

  workstation.host = {
    name = machine.host;
    inherit (machine) user;
    homeDirectory = machine.home;
  };
  workstation.enable = true;
  networking.hostName = config.workstation.host.name;
  users.users.${machine.user}.home = machine.home;
  system.primaryUser = machine.user;

  nix-homebrew = {
    enable = true;
    inherit (machine) user;
    autoMigrate = true;
  };
  homebrew.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${machine.user}.imports = machine.homeModules ++ [ homePlane ];
  };

  system.stateVersion = 5;
}
