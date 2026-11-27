# The plane hubs: `flake.modules.<class>.workstation` imports the plane core
# plus every domain module of that class.
# | Hub | Core |
# | --- | --- |
# | homeManager | nix/modules/workstation-home.nix, nix/modules/routines-home.nix |
# | nixos, darwin | nix/modules/workstation-system.nix, nix/modules/host.nix, nix/modules/routines-system.nix |
{ config, lib, ... }:
let
  domains =
    class: lib.attrValues (removeAttrs (config.flake.modules.${class} or { }) [ "workstation" ]);
  system = [
    ../modules/workstation-system.nix
    ../modules/host.nix
    ../modules/routines-system.nix
  ];
in
{
  flake.modules.homeManager.workstation.imports = [
    ../modules/workstation-home.nix
    ../modules/routines-home.nix
  ]
  ++ domains "homeManager";

  flake.modules.nixos.workstation.imports = system ++ domains "nixos";
  flake.modules.darwin.workstation.imports = system ++ domains "darwin";
}
