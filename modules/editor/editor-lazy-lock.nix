# The lazy-lock merge: the committed baseline pins merged into the live,
# runtime-extended ~/.config/nvim/lazy-lock.json at apply.
{ wsLib, ... }:
{
  flake.modules.homeManager.editor =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };

      lazyLockBaseline = ./files/lazy-lock-baseline.json;

      merge = ws.script {
        name = "workstation-lazy-lock-merge";
        inputs = [
          pkgs.coreutils
          pkgs.jq
        ];
        file = ./files/lazy-lock-merge.sh;
      };
    in
    {
      config = ws.whenOn "editor" {
        # the merge runs after the deploy: the deploy owns the config tree,
        # the merge owns the live lockfile beside it
        home.activation.merge-lazy-lock = lib.hm.dag.entryAfter [ "writeBoundary" "deploy-nvim-config" ] ''
          lock="$HOME/.config/nvim/lazy-lock.json"
          if ${merge}/bin/workstation-lazy-lock-merge ${lazyLockBaseline} "$lock" > "$lock.merged"; then
            mv "$lock.merged" "$lock"
            echo "workstation: lazy-lock merge applied (${config.home.homeDirectory}/.config/nvim/lazy-lock.json)"
          else
            rm -f "$lock.merged"
            echo "workstation: lazy-lock merge failed — the live lockfile is untouched" >&2
            exit 1
          fi
        '';
      };
    };
}
