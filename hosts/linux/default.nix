# The linux system leg (NixOS-WSL): the host identity, WSL, mosh, nix-ld
# and the machine's home plane through home-manager. Applied by
# nix/flake/legs.nix with importApply.
{
  machine,
  homePlane,
  pkgs,
}:
{ config, lib, ... }:
{
  nixpkgs.pkgs = pkgs;

  workstation.enable = true;
  programs.mosh.enable = true;
  # mise-managed prebuilt toolchains exec through nix-ld
  programs.nix-ld = {
    enable = true;
    libraries = [ pkgs.stdenv.cc.cc ];
  };

  workstation.host = {
    name = machine.host;
    inherit (machine) user;
    homeDirectory = machine.home;
  };

  wsl = {
    enable = true;
    defaultUser = lib.mkIf (machine.user != "root") machine.user;
  };
  networking.hostName = config.workstation.host.name;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${machine.user}.imports = machine.homeModules ++ [ homePlane ];
  };

  system.stateVersion = "25.05";
}
