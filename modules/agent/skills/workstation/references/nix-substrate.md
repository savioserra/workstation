# Nix substrate conventions (the workstation's nixpkgs-native repo)

The workstation repo IS a nixpkgs-native flake: nix owns build, pins, the file plane, activation and rollback. The structure's home is `docs/architecture.md` at HEAD. This file carries the durable conventions for touching the substrate.

## The repo shape

- `flake.nix` — ONE nixpkgs input (`nixos-unstable`; home-manager master and nix-darwin following it), one `pkgsFor` instance per system (`import nixpkgs { inherit system; config.allowUnfreePredicate = …; }`), no overlays, no version floors — `flake.lock` is the tool version surface. Outputs: `workstation.report.<verb>`, `homeConfigurations` (linux leg), `darwinConfigurations`, `nixosConfigurations`, the checks; host keys come from the machine file.
- `modules/<domain>/` — module + payload bytes CO-LOCATED. `modules/default.nix` is the explicit import list; every leg imports all modules and each gates on its own enable. A domain DECLARES its own options (`options.workstation.<domain>.enable`, members `workstation.<domain>.<member>.enable`); there is no central options file and no filesystem walk. A domain contributes to another only through an option that domain declares, guarded by its own enable; no path imports across domains.
- **Tools live with their consumers** and use upstream modules where they exist: foundation = `programs.bash/zsh/direnv` + fd/rg/lazygit/mise/newt; terminal = `programs.eza/starship` + tmux/nunchux members; editor = neovim + its session variables; languages = scoped runtimes; agent = the hermes pin declared IN the module.
- `hosts/{linux,mac}/default.nix` — the system legs, fed by `nix/lib/machine.nix`.
- `bin/workstation` — the POSIX shim: resolves the checkout (`--flake` > `$WORKSTATION_FLAKE` > enclosing checkout > `$WORKSTATION_CHECKOUT`, baked into the launcher from the machine file's `checkout`), builds `git+file://<checkout>?rev=<HEAD>` (only when the dir is the git toplevel) with `--override-input machine-files path:<checkout>/hosts/local`; reads are `nix eval`s over `workstation.report.<verb>`, `add|remove|fleet` edit `hosts/local/machine.json` with jq, writes delegate to `nix/workstation-switch.nix` through env (`WORKSTATION_SWITCH_FLAKE|MACHINE|CHECKOUT`) — the driver carries no repo copy; it builds the activationPackage, runs its activate, and receipts `generation N applied … at <rev>` in `~/.local/state/workstation/switch.log`, the rev parsed from the ref's `?rev=`. `update` only moves `flake.lock` (commit it, then apply). `WORKSTATION_WORKTREE=1` builds the working tree.
- `nix/report.nix` — one home eval; attribution per capability from `options.<x>.definitionsWithLocations`.
- `tests/nix/` — the CONTAINER E2E (`run-container.sh`, `e2e.nix` driver, `e2e-home.nix` persona, `e2e-selections*.nix` flag modules). The VM lane sits outside the battery (no nested KVM on cloud hosts); system planes stay eval-only.

## The machine file

`hosts/template/{machine.json,peers.nix}` are the TRACKED templates (`host`, `user`, `home`, `system`, `settings` with TEMPLATE placeholders). `workstation init` seeds `hosts/local/` (gitignored) from them and captures the machine there (whiptail, prefilled from detection; `checkout` recorded); `settings` is a raw home-manager option tree applied as a module, so the module system validates every flag. The identity gate reds on personal strings in the tracked tree (doc examples as `<user>@<host>`).

- The machine files reach the flake as a non-flake input `machine-files = { url = "path:./hosts/template"; flake = false; }` (relative path inputs need nix ≥ 2.26): the template is the default (CI evals the TEMPLATE keys), the shim overrides it with `path:<checkout>/hosts/local`. A `path:` input copies the directory as-is, so gitignored files ARE visible through the override while a `?rev=` build of the repo excludes them and all work in progress. Nix DROPS `self.rev`/`self.dirtyRev` once any input is overridden (the lock is modified), so under the override `self.rev` evaluates to the fallback — name the commit from the ref the launcher built (`?rev=`), keeping `workstation.rev = self.rev or …` only for override-free evals (CI). Never stage `self` (or the rev) inside a generation, or every commit changes it. The override prints a 'not writing modified lock file' warning on stderr; stdout stays clean.
- Keep machine data UNTRACKED, never as modified tracked files: a dirty tracked file blocks `git pull` (rebase-configured pulls refuse any unstaged change), and stash-based workarounds misfire — `git stash push` that finds nothing creates no stash, so an unconditional `pop` applies an older UNRELATED stash, and `stash push --` with no paths stashes every change. If a script must stash, stash only when `git diff --quiet -- <paths>` says dirty, record `refs/stash` after the push, pop only that one, and fail loudly on a pop conflict.
- New tracked files must be git-added (`git add -N` suffices) before any `nix eval` of the repo sees them.
- When a landing changes the machine-file SHAPE or location, move each host with a one-off out-of-repo step: back up, `git checkout --` the tracked copies, pull, restore into the new place, apply, prove (references/architecture-review.md, 'Implementing the ruled steps').
- Selection: `workstation add|remove <path>` sets/drops `settings.workstation.<path>.enable` (validated against `workstation.report.selectable`); `workstation selected` renders on/off/baseline per path. Domains default ON, `network` and language members OFF, foundation is baseline (no enable).

## Verification

- Battery: `sh .github/scripts/check.sh` with nix + the flakes `NIX_CONFIG` — identity gate, history-prose gate, ShellCheck over `bin/ modules/ .github/scripts/ tests/ hosts/` + `install.sh`, the shim dispatch test, the report eval gate. Put shellcheck and nixfmt on PATH or the gates silently skip.
- check.sh does NOT eval the legs: eval `nixosConfigurations.TEMPLATE`, `darwinConfigurations."TEMPLATE@TEMPLATE"`, `checks.x86_64-linux.e2e-home`/`e2e-driver` yourself; prove real host keys on a scratch copy with the machine files overlaid.
- **Behavioral proof is the container E2E plus consumer smokes on the BUILT generation** (`<gen>/home-files/...`) — no byte goldens.
- **Convergence proof on a standalone-HM leg**: the live generation is an indirection (`/nix/var/nix/profiles/per-user/<user>/profile-<N>-link` → a `-profile` store path), so it never string-equals the built `activationPackage` path. Prove convergence with the switch.log receipt (rev matches HEAD) plus a consumer smoke of the package in the live profile closure (`nix-store -qR <profile-path> | grep <tool>` and `<tool> --version` from PATH).
- Format before landing: nixfmt (RFC 166) over every tracked and new `.nix`.

## Module conventions (nixpkgs-idiomatic)

- No `with`, no `rec`, no `<nixpkgs>`, no `builtins.getEnv`, no `fetchTarball`.
- Options: explicit type + description; `lib.mkEnableOption` (default-on via `// { default = true; }`); `lib.mkIf`/`lib.mkMerge`; `assertions` for validation; `pkgs.stdenv.hostPlatform.isDarwin`, never the deprecated `stdenv.isDarwin`.
- Shell init through upstream `programs.*` with `lib.mkOrder`; env through `home.sessionVariables`; rc snippets as nix strings (references/nix-module-system-pitfalls.md).
- `home.backupFileExtension = "hm-backup"` in the home plane (every leg; no leg-specific `home-manager.backupFileExtension`): standalone home-manager otherwise REFUSES a first switch over any existing unmanaged file (a distro `.bashrc`) — the CLI's `-b` is not in play under the launcher.
- Activation hooks print ONE message per outcome: a wrapper `|| echo "… failed"` around a program that already explained itself contradicts it; use `|| true` and let the program speak.
- Removing a deployed file = dropping its declaration; the generation diff removes it. Paths the file plane never owned are the operator's — no tombstone lists.
- No prose in code: terse what-it-does headers only.

## Principles

- **Switch-time push, not streaming**: consumers are notified once per switch (the theme module re-points a token path each generation). Nothing polls.
- **Build proofs are container proofs**; hermeticity claims are verified by tampering (a checksum-modified input must FAIL).
- **A package that names a tool ships the tool** — only invoking the tool proves it.
- **A generation is a commit**: built from `?rev=<HEAD>` plus the machine files; a docs-only commit leaves home and darwin generations byte-identical (prove a contract change with a scratch clone: build, commit a doc edit, rebuild, compare outPaths; a dirty edit must not move the `?rev=` build).

## Pitfalls that cost hours

- **Verify against the FILE, never the transcript, before editing a 'corrupted' string**: tool output passes a display scrubber that masks literal patterns. `python3 -c "print(pattern in open(f).read())"` settles it.
- `nix eval --raw` on an unbuilt output returns the path string without building — use `nix build --no-link --print-out-paths`.
- `lib.generators.toLua` emits a bare table — a lua module file needs `return `; smokes must exercise the COMPOSED case (nvim headless with all language modules).
- Eval-time file reads (`builtins.readFile`) must take repo paths, never derivations: a derivation is import-from-derivation and the darwin leg's eval on the x86 runner dies on `Required system: aarch64-darwin`.
- A test asserting repo state (the machine file still TEMPLATE) must build that state in its own fixture.
- **CI is the release gate**: `release.yml` re-runs CI before publishing a tag; `gh` needs a checkout cwd.
- **`git checkout -- <file>` reverts to HEAD, not to your pre-edit state**: after a landing, HEAD already carries the just-committed line, so a checkout meant to undo a probe edit restores the committed bug and the eval keeps failing on the same line. Undo working-tree edits with the patch tool, and after any checkout re-grep the file for the line under test before re-running the eval.

## Settled rulings (do not re-litigate)

- **One channel, no overlays, no floors** — nixos-unstable carries every tool. The inline-pin exceptions (herdr, the tmux/nunchux checkouts, the hermes checkout) are declared in their owning modules.
- **The operator surface is one verb** — `workstation init` / `apply` / `add|remove` / `fleet` / `peers`; leg-native verbs never appear in user-facing flows.
- **Host-side experimentation is host-local**: payload edits stay UNCOMMITTED in the working copy and stay OUT of the generation (applies build the committed HEAD); `WORKSTATION_WORKTREE=1` deploys them on request; land only the operator's verdict.
- **No per-tool verify scripts**: store paths and nixpkgs already guarantee the bits, so pin-manifest checks and 'checkout at commit X' smokes are redundant; consumer checks live in the container e2e. A verify lane survives only for state nix does not own (the activation-cloned hermes checkout).
- **Homebrew on darwin is a managed dependency** via nix-homebrew (pinned brew, autoMigrate); the darwin leg never runs brew update/upgrade on activation (references/host-first-switch-macos.md).
- **system-manager for standalone-linux daemons is TBD**: adopt it only when it carries the NixOS service module the domain needs (check `nix/modules/upstream/nixpkgs/` in its source) — otherwise it re-declares the same hand-written unit, adds a root switch and a live transport first switch for no gain.
