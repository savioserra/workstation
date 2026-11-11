# The editor domain: neovim, the nvim config tree (deployed by activation,
# writable, pruned by the managed list), the composed language profile and
# the lazy-lock merge.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
  nvim = pkgs.neovim;
  cfg = config.workstation.editor;

  payloadNvim = ./nvim/files/.config/nvim;
  lazyLockBaseline = payloadNvim + "/lazy-lock.json";

  extrasPrefix = "lazyvim.plugins.extras.";

  standardEntry = {
    id = "standard";
    lazyvim_extras = map (e: extrasPrefix + e) [
      "lang.docker"
      "lang.json"
      "lang.markdown"
      "lang.tailwind"
      "lang.toml"
      "lang.yaml"
    ];
  };

  languages = lib.mapAttrsToList (id: l: l // { inherit id; }) cfg.languages;

  entryOf =
    l:
    lib.filterAttrs (_: v: v != null && v != [ ]) {
      inherit (l) id requires;
      lazyvim_extras = map (e: extrasPrefix + e) l.extras;
      mason_packages = l.mason;
      plugin_module = if l.plugin == null then null else "languages.plugins.${l.id}";
    };

  entries = lib.sort (a: b: a.id < b.id) ([ standardEntry ] ++ map entryOf languages);

  profileLua = "return " + lib.generators.toLua { } entries + ";";

  mergeLua =
    builtins.replaceStrings
      [ "__WORKSTATION_LAZY_LOCK_BASELINE__" ]
      [
        (builtins.readFile lazyLockBaseline)
      ]
      (builtins.readFile ./nvim/files/lazy-lock-merge.lua);

  mergeProgram = pkgs.writeText "ws-lazy-lock-merge.lua" mergeLua;

  configTree = pkgs.runCommand "ws-editor-nvim-config" { } ''
    set -euo pipefail
    mkdir -p "$out"
    cp -a ${payloadNvim}/. "$out/"
    chmod -R u+w "$out"
    # the lock is runtime-extended application state — the tree never
    # carries it; the merge activation seeds the live copy
    rm -f "$out/lazy-lock.json"
    mkdir -p "$out/lua/languages/plugins"
    cp ${pkgs.writeText "languages-profile.lua" profileLua} "$out/lua/languages/profile.lua"
    ${lib.concatMapStringsSep "\n" (
      l: ''cp -a "${l.plugin}" "$out/lua/languages/plugins/${l.id}.lua"''
    ) (builtins.filter (l: l.plugin != null) languages)}
  '';
in
ws.capability [ "editor" ] {
  description = "neovim and the composed language profile";
  default = true;
  options.languages = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          requires = lib.mkOption {
            type = lib.types.listOf lib.types.nonEmptyStr;
            default = [ ];
            description = "Host capability ids the entry needs (the profile's `requires`).";
          };
          extras = lib.mkOption {
            type = lib.types.listOf lib.types.nonEmptyStr;
            default = [ ];
            description = "LazyVim extras under lazyvim.plugins.extras (`lang.go`), imported before the base specs.";
          };
          mason = lib.mkOption {
            type = lib.types.listOf lib.types.nonEmptyStr;
            default = [ ];
            description = "Mason packages (each pinned in mason-lock.json).";
          };
          plugin = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "The lazy.nvim spec module, deployed as lua/languages/plugins/<id>.lua and imported after the base specs.";
          };
        };
      }
    );
    default = { };
    description = "Language entries keyed by profile id, composed into lua/languages/profile.lua.";
  };

  config = {
    home.packages = [ pkgs.tree-sitter ];

    home.sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      GIT_EDITOR = "nvim";
    };

    home.file = {
      ".local/bin/nvim".source = "${nvim}/bin/nvim";
    };

    home.activation.deploy-nvim-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      tree="$HOME/.config/nvim"
      src="${configTree}"
      list="${config.home.homeDirectory}/.local/state/workstation/nvim-managed.list"
      # the prune: the previous deploy's managed paths dropped by this
      # tree — a fresh host carries no list and prunes nothing
      if [ -f "$list" ]; then
        while IFS= read -r rel || [ -n "$rel" ]; do
          [ -n "$rel" ] || continue
          if [ ! -e "$src/$rel" ]; then
            rm -f -- "$tree/$rel"
            d=$(dirname -- "$tree/$rel")
            while [ "$d" != "$tree" ]; do
              rmdir -- "$d" 2>/dev/null || break
              d=$(dirname -- "$d")
            done
          fi
        done < "$list"
      fi
      mkdir -p "$tree"
      cp -a "$src/." "$tree/"
      # the store modes are read-only; the deployed copy must stay
      # writable or the next apply (and the lazy-lock merge) fails
      chmod -R u+w "$tree"
      # the deployed paths are the next apply's prune set
      mkdir -p -- "$(dirname -- "$list")"
      ${pkgs.findutils}/bin/find "$src" -mindepth 1 -type f -printf '%P\n' > "$list.new"
      mv -f -- "$list.new" "$list"
      echo "workstation: nvim config synced (${config.home.homeDirectory}/.config/nvim)"
    '';

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
