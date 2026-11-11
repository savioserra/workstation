# The terminal domain: eza (ls) and the starship prompt.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
in
ws.capability [ "terminal" ] {
  description = "eza, starship, mosh, tmux and nunchux";
  default = true;
  config = {
    home.packages = [ pkgs.mosh ];
    programs.eza = {
      enable = true;
      icons = "auto";
      extraOptions = [ "--group-directories-first" ];
    };
    home.shellAliases.ls = "eza -lh";

    programs.starship.enable = true;
    xdg.configFile."starship.toml".source = ./starship.toml;
  };
}
