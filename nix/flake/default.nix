# The flake's top-level configuration (flake-parts).
# | File | Owns |
# | --- | --- |
# | systems.nix | the systems, one nixpkgs instance per system |
# | machines.nix | the machine files: the captured machine and the template ones |
# | planes.nix | the home and system plane hubs (`flake.modules.<class>.workstation`) |
# | legs.nix | the leg builders: home, linux (NixOS-WSL), mac (nix-darwin) |
# | outputs.nix | the machine's configurations and `workstation` (report, rev, keys) |
# | checks.nix | the check surface on the CI system |
{ inputs, ... }:
{
  imports = [
    inputs.flake-parts.flakeModules.modules
    inputs.home-manager.flakeModules.home-manager
    inputs.nix-darwin.flakeModules.default
    ./systems.nix
    ./machines.nix
    ./planes.nix
    ./legs.nix
    ./outputs.nix
    ./checks.nix
  ];
}
