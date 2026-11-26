# The terminal domain: eza (ls), the starship prompt, btop and mosh.
# | File | Owns |
# | --- | --- |
# | terminal.nix | eza, starship |
# | terminal-mosh.nix | mosh and the session-vars mosh-server wrapper |
# | terminal-btop.nix | btop and its theme consumer |
{ wsLib, ... }:
{
  imports = [
    ./terminal-btop.nix
    ./terminal-mosh.nix
    ./zellij/zellij.nix
  ];

  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };
    in
    ws.capability [ "terminal" ] {
      description = "eza, starship, mosh, btop and zellij";
      default = true;
      config = {
        programs.eza = {
          enable = true;
          icons = "auto";
          extraOptions = [ "--group-directories-first" ];
        };
        home.shellAliases.ls = "eza -lh";

        programs.starship.enable = true;
        xdg.configFile."starship.toml".source = ./starship.toml;
      };
    };
}
