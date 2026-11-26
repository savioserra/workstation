# The fonts domain: the JetBrainsMono Nerd Font and fontconfig discovery.
{ wsLib, ... }:
{
  flake.modules.homeManager.fonts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };
      fontTree = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono";
      fontTarget =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "Library/Fonts/JetBrainsMonoNerdFont"
        else
          ".local/share/fonts/JetBrainsMonoNerdFont";
    in
    ws.capability [ "fonts" ] {
      description = "the JetBrainsMono Nerd Font";
      default = true;
      config = {
        home.file.${fontTarget}.source = fontTree;
        fonts.fontconfig.enable = true;
      };
    };
}
