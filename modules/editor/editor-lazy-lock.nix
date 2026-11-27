# The lazy-lock merge: the payload baseline merged into the live,
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
      nvim = pkgs.neovim;

      lazyLockBaseline = ./nvim/files/.config/nvim/lazy-lock.json;

      mergeLua =
        builtins.replaceStrings
          [ "__WORKSTATION_LAZY_LOCK_BASELINE__" ]
          [
            (builtins.readFile lazyLockBaseline)
          ]
          (builtins.readFile ./nvim/files/lazy-lock-merge.lua);

      mergeProgram = pkgs.writeText "ws-lazy-lock-merge.lua" mergeLua;

    in
    {
      config = ws.whenOn "editor" {
        # the merge runs after the deploy: the deploy owns the config tree,
        # the merge owns the live lockfile beside it
        home.activation.merge-lazy-lock = lib.hm.dag.entryAfter [ "writeBoundary" "deploy-nvim-config" ] ''
          lock="$HOME/.config/nvim/lazy-lock.json"
          if [ -f "$lock" ]; then
            ${nvim}/bin/nvim -l "${mergeProgram}" < "$lock" > "$lock.merged"
          else
            ${nvim}/bin/nvim -l "${mergeProgram}" < /dev/null > "$lock.merged"
          fi
          mv "$lock.merged" "$lock"
          echo "workstation: lazy-lock merge applied (${config.home.homeDirectory}/.config/nvim/lazy-lock.json)"
        '';
      };
    };
}
