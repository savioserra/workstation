# Architecture review of the substrate (critique against nixpkgs-native)

The operator's target: per-machine flags (`network = true`,
`languages.go = true`) select domains; nixpkgs and the module system resolve
everything else; domains are self-contained and never reach into each other.
A review measures the tree against that, with evidence, and proposes — it
never implements before the operator rules.

## Procedure

1. Load this skill + `nix-module-system-pitfalls.md`; read `flake.nix`,
   `nix/lib/*.nix`, `nix/modules/*.nix`, every `modules/*/overlay.nix`, the
   legs in `hosts/`, then one member module (a language) end to end.
2. Ownership map — which module touches which foreign namespace (python over
   `git ls-files 'modules/*.nix' 'nix/**/*.nix'`, comments stripped, regex
   `workstation\.<x>(\.<y>)?|programs\.hermes\.<x>|pkgs\.workstation-<x>|self + "/modules/<x>`;
   print only namespaces outside the file's own domain). Add path imports
   across domains (`import ../../<other>/`) and system modules reading
   `../../modules/<domain>/files`.
3. Upstream reuse — `git grep -ohE '\b(programs|services|fonts|xdg)\.[a-z0-9_-]+\.(enable|package|plugins|initContent)'`;
   compare against hand-rolled equivalents (rc files, tmux plugin pins,
   prompt, activation scripts).
4. Eval cost — `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=$TMPDIR/st.json nix eval --raw --option eval-cache false '<leg attr>.drvPath'`,
   then `jq '{cpu: .cpuTime, thunks: .nrThunks, heapMB: (.gc.heapSize/1048576|floor)}'`.
   `NIX_SHOW_STATS` writes to stderr mixed with warnings — always use the
   `_PATH` form.
5. Instantiation count — copy the tree to scratch (`git ls-files -z | xargs -0 tar -cf - | tar -xf - -C <d>`
   plus the uncommitted machine files and `flake.lock`), insert
   `builtins.trace "PROBE" nixpkgs.lib.composeManyExtensions (` in the
   overlay (trace returns the function, so currying stays intact; wrapping an
   `import x { }` needs `(import x)`), eval via `path:<d>#<attr>` and
   `grep -c PROBE`. Never edit the live checkout for a probe.
6. Live read verbs — run `nix eval --json .#workstation.report.status` and
   `workstation selected` on a REAL host checkout (its selections pinned):
   template evals hide failures that only a host's pins trigger.
7. Research primary sources (below) for each proposed replacement; check the
   pinned channel against endoflife.date/nixos.

## Output shape

A report file outside the repo (`/root/reports/<topic>.md`), tables only:
verdict per axis → evidence probes with numbers → findings
(`# | finding | where | nix-native answer | severity`) → keep list → target
shape with one domain-module example → move steps, each landing alone
with its proof and both hosts re-converged → sources. The chat reply carries
the verdict, any live bug found, the top findings and the next decision.

## Implementing the ruled steps

One plan step = one commit pushed to `main`, then both hosts converge before
the next step starts. Per step:

1. Work in the release worktree on a feature branch from `origin/main`.
   Write each multi-file edit as a scratch python script (`$TMPDIR/arch/stepN*.py`)
   with `assert s.count(old) == 1` per replacement.
2. Gates, in order: nixfmt on every tracked/new `.nix` → evals of every leg
   (nixos/darwin TEMPLATE toplevel, `checks.<sys>.e2e-home`, `e2e-driver`) →
   the real host keys through a scratch copy with the machine files overlaid
   (never the live checkout) → build the real host's generation and read its
   rendered files / diff it against the live one → the battery → commit
   locally (the container e2e extracts `git archive HEAD`; uncommitted work
   is not under test) → the container e2e (`sh tests/nix/run-container.sh
   <log>` in background + notify; it catches builder-env bugs the host build
   hides) → amend fixes and re-run.
   A step that claims generation invariance proves it on a scratch clone
   (`git clone -q . <d>`), evaluating the real host key's `outPath` with the
   host's machine files overridden: A = `git+file://<d>?rev=<HEAD>`; B = the
   same after a docs-only commit; C = B's ref with a dirty payload edit;
   D = `git+file://<d>` (worktree) with that edit. Pass: A = B = C, C ≠ D.
   Repeat for the darwin key's toplevel.
3. Old-vocabulary sweep: `git grep -nIE '<old file names>|<old option names>|<old mechanism words>'`
   across docs, tests, workflows, scripts and comments; rewrite to the current
   world in the same commit; repeat until zero hits.
4. Commit, push `HEAD:main`, converge each host in its own pane (one-liner
   printing `CONVERGED at <sha>` / `DRIFT`).
5. When a step changes the uncommitted machine-file shape (old files deleted
   by the pull), migrate with a one-off script kept OUT of the repo: back up
   the old files, build the new file from them (`nix eval --impure --json
   --expr` over the imported old files — no nixpkgs lib needed), pull,
   write, restore `peers`. Give it a dry-run mode and prove its output equals
   the hand-built expected file before running it on a host; make it a no-op
   when the new file is already captured.
6. Report a step table (step | commit | host gens) plus the open decisions.
7. When the operator asks to EXPLAIN a step instead of implementing it
   (a cross-plane move like per-domain system modules), answer with a
   current-state table (where | what | why it breaks the boundary), the
   numbered target changes, the generation/host impact (which host needs
   sudo), and one go/no-go question — no code until he rules.

## Nix-native answers (reference set)

| Smell | Answer |
| --- | --- |
| second nixpkgs channel + overlays to get newer tools | track one current channel (stable or unstable) with HM/nix-darwin on the matching branch |
| overlay as a domain's package choice (global, unconditional) | `package = lib.mkPackageOption pkgs "<name>" { };` in the domain; an extra package set arrives as a module arg, never an overlay |
| `import nixpkgs { … }` repeated; standalone HM given `pkgs` AND `nixpkgs.overlays` | one `pkgs` per system (`legacyPackages.${system}` when no overlay/config is needed); HM's `modules/misc/nixpkgs.nix` re-imports nixpkgs from `nixpkgs.*` options |
| filesystem walk / probe to discover modules | explicit `imports` list per domain, or import-tree |
| string selection lists translated to enables | machine file mapped onto options (`{ config = (lib.importJSON (machineFiles + "/machine.json")).settings; }`); the module system rejects unknown flags and wrong types |
| machine data as modified tracked files (pulls blocked, stash dances) | tracked `hosts/template/`, untracked gitignored `hosts/local/` seeded by init, read through a `path:` input override (path inputs see gitignored files) |
| enables declared in a central options file | each domain declares `options.workstation.<domain>`; an extension point is declared by the consuming domain, contributors guard with `mkIf config.workstation.<other>.enable` |
| a domain's system half in a generic system module | per-domain `home.nix` / `nixos.nix` / `darwin.nix` (dendritic pattern = one feature file across classes) |
| hand-written rc lanes, tmux plugin checkouts | `programs.bash/zsh` (`initContent` + `lib.mkOrder`), `programs.starship/eza/fzf/direnv/go/tmux` |
| system daemons written from a home activation on non-NixOS linux | system-manager (Ubuntu/Debian/NixOS, systemd) — only if its `nix/modules/upstream/nixpkgs/` carries the service's NixOS module (probe: `nix flake prefetch --json github:numtide/system-manager` → `ls <storePath>/nix/modules/upstream/nixpkgs`; it ships firewall, nginx, nix, openssh, ssh, sudo, security-wrappers, userborn, users-groups — no tailscale); else it is the same hand-written unit plus a root switch (rule TBD, explain the trade) |
| per-capability HM evals to attribute files | one eval + `options.home.file.definitionsWithLocations` |
| `self` snapshot in the home generation | build `git+file://<checkout>?rev=<HEAD>`, the machine files through a `path:./hosts/template` non-flake input overridden per host with `hosts/local`; the switch receipt names the commit from the ref's `?rev=` (nix drops `self.rev` under any `--override-input`), never stamped into the generation |
| Homebrew on darwin hand-installed or absent | `nix-homebrew` darwin module (nixpkgs has no homebrew): pins brew via its lock, `autoMigrate` adopts an existing install; packages via nix-darwin `homebrew.*` |
| `assert … \|\| throw` in `let` | `assertions = [ { assertion; message; } ]` |

## Sources

nix.dev module-system deep dive; nixpkgs `lib/options.nix`; NixOS manual
'Writing NixOS Modules'; zimbatm '1000 instances of nixpkgs'; flake.parts
overlays page; github.com/mightyiam/dendritic; github.com/vic/import-tree;
system-manager.net; home-manager `programs.zsh.initContent`; nixos.org
release announcements + endoflife.date/nixos.
