# The elixir member: the beam toolchain and its editor profile entry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../../nix/lib/capability.nix { inherit config lib pkgs; };
in
ws.capability [ "languages" "elixir" ] {
  description = "the elixir toolchain and its editor profile";
  config = {
    home.packages = [ pkgs.beam.packages.erlang_28.elixir ];
    workstation.editor = ws.whenOn "editor" {
      languages = [
        {
          id = "elixir";
          lazyvim_extras = [ "lazyvim.plugins.extras.lang.elixir" ];
          mason_packages = [ "elixir-ls" ];
          plugin_module = "languages.plugins.elixir";
        }
      ];
      languagePlugins = [ ./files/languages/plugins/elixir.lua ];
    };
  };
}
