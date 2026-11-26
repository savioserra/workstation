# The plane hubs: `flake.modules.homeManager.workstation` (the home plane:
# launcher, switch driver, every capability) and `flake.modules.{nixos,darwin}.workstation`
# (the system plane).
{
  flake.modules.homeManager.workstation = ../modules/workstation-home.nix;

  flake.modules.nixos.workstation.imports = [
    ../modules/workstation-system.nix
    ../modules/host.nix
    ../../modules/network/system.nix
  ];

  flake.modules.darwin.workstation.imports = [
    ../modules/workstation-system.nix
    ../modules/host.nix
    ../../modules/network/system.nix
  ];
}
