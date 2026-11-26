# mosh, with a wrapper whose --server sources the home-manager session vars.
{ wsLib, ... }:
{
  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };

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
    {
      config = ws.whenOn "terminal" {
        home.packages = [
          pkgs.mosh
          mosh
        ];
      };
    };
}
