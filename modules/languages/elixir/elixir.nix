# The elixir member: the mise-pinned beam toolchain and its editor profile
# entry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  lang = import ../../../nix/lib/language.nix { inherit config lib pkgs; };
in
lang.language [ "languages" "elixir" ] {
  description = "the beam toolchain and its editor profile";
  tools = {
    elixir = "1.20.5-otp-28";
    erlang = {
      version = "28.5.0.8";
      # prebuilt platforms only — never a kerl source build
      compile = false;
    };
  };
  editor = {
    extras = [ "lang.elixir" ];
    mason = [ "elixir-ls" ];
    plugin = ./files/languages/plugins/elixir.lua;
  };
}
