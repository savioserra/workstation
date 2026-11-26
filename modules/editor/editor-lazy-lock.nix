# The lazy-lock merge: the payload baseline merged into the live,
# runtime-extended ~/.config/nvim/lazy-lock.json at apply.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
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
    home.activation.merge-lazy-lock = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      lock="$HOME/.config/nvim/lazy-lock.json"
      work=$(mktemp)
      trap 'rm -f "$work"' EXIT
      cp ${mergeProgram} "$work"
      if [ -f "$lock" ]; then
        ${nvim}/bin/nvim -l "$work" < "$lock" > "$lock.merged"
      else
        ${nvim}/bin/nvim -l "$work" < /dev/null > "$lock.merged"
      fi
      mv "$lock.merged" "$lock"
      echo "workstation: lazy-lock merge applied (${config.home.homeDirectory}/.config/nvim/lazy-lock.json)"
    '';
  };
}
