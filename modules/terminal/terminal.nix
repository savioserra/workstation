# The terminal domain: eza (ls), the starship prompt, btop, mosh and the
# tmux multiplexer.
# | File | Owns |
# | --- | --- |
# | terminal.nix | eza, starship |
# | terminal-mosh.nix | mosh and the session-vars mosh-server wrapper |
# | terminal-btop.nix | btop and its theme consumer |
# | tmux/tmux.nix | the tmux multiplexer, the tmux2k status bar, the theme consumer |
{ wsLib, ... }:
{
  imports = [
    ./terminal-btop.nix
    ./terminal-mosh.nix
    ./tmux/tmux.nix
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
      description = "eza, starship, mosh, btop and tmux";
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
