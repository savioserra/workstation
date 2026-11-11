# The terminal domain: eza (ls), the starship prompt, btop and mosh.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };

  # the remote mosh-server under the home-manager session vars (the profile
  # PATH, LOCALE_ARCHIVE_2_27): an ssh command on a bash host sources none
  moshServer = lib.concatStrings [
    ''for f in "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"; do [ -r "$f" ] && . "$f"; done; ''
    ''PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH" mosh-server''
  ];
  mosh = lib.hiPrio (
    pkgs.writeShellScriptBin "mosh" ''
      for arg in "$@"; do
        case $arg in
        --server | --server=*) exec ${pkgs.mosh}/bin/mosh "$@" ;;
        esac
      done
      exec ${pkgs.mosh}/bin/mosh --server=${lib.escapeShellArg moshServer} "$@"
    ''
  );
in
ws.capability [ "terminal" ] {
  description = "eza, starship, mosh, btop, tmux and nunchux";
  default = true;
  config = {
    home.packages = [
      pkgs.mosh
      mosh
      pkgs.btop
    ];
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
