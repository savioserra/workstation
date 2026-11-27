# The nvim config tree: the payload plus the composed language profile
# (lua/languages/profile.lua and each entry's plugin module), deployed
# writable to ~/.config/nvim and pruned by the managed list.
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
      cfg = config.workstation.editor;

      payloadNvim = ./nvim/files/.config/nvim;

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

      configTree = pkgs.runCommand "ws-editor-nvim-config" { } ''
        set -euo pipefail
        mkdir -p "$out"
        cp -a ${payloadNvim}/. "$out/"
        chmod -R u+w "$out"
        mkdir -p "$out/lua/languages/plugins"
        cp ${pkgs.writeText "languages-profile.lua" profileLua} "$out/lua/languages/profile.lua"
        ${lib.concatMapStringsSep "\n" (
          l: ''cp -a "${l.plugin}" "$out/lua/languages/plugins/${l.id}.lua"''
        ) (builtins.filter (l: l.plugin != null) languages)}
      '';
    in
    {
      config = ws.whenOn "editor" {
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
      };
    };
}
