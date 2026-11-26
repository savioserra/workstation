# The leg builders, each over a machine.nix view:
# | Leg | Builds |
# | --- | --- |
# | home | standalone home-manager over the system's nixpkgs |
# | linux | NixOS-WSL with the machine's home plane (hosts/linux), the system's nixpkgs read-only |
# | mac | nix-darwin, Homebrew pinned by nix-homebrew, the home plane (hosts/mac), the system's nixpkgs |
{
  config,
  inputs,
  lib,
  withSystem,
  flake-parts-lib,
  ...
}:
let
  inherit (flake-parts-lib) importApply;
  planes = config.flake.modules;
  hostModule =
    path: machine:
    importApply path {
      inherit machine;
      homePlane = planes.homeManager.workstation;
      pkgs = withSystem machine.system ({ pkgs, ... }: pkgs);
    };
in
{
  options.workstation.legs = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    readOnly = true;
    description = "The leg builders: home (system → modules → configuration), linux and mac (machine → configuration).";
  };

  config.workstation.legs = {
    home =
      system: modules:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = withSystem system ({ pkgs, ... }: pkgs);
        modules = modules ++ [ planes.homeManager.workstation ];
      };

    linux =
      machine:
      inputs.nixpkgs.lib.nixosSystem {
        modules = [
          inputs.nixpkgs.nixosModules.readOnlyPkgs
          inputs.nixos-wsl.nixosModules.default
          planes.nixos.workstation
          inputs.home-manager.nixosModules.home-manager
          (hostModule ../../hosts/linux machine)
        ];
      };

    mac =
      machine:
      inputs.nix-darwin.lib.darwinSystem {
        modules = [
          planes.darwin.workstation
          inputs.home-manager.darwinModules.home-manager
          inputs.nix-homebrew.darwinModules.nix-homebrew
          (hostModule ../../hosts/mac machine)
        ];
      };
  };
}
