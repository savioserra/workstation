# First switch on a host (converging onto the substrate)

- Scope: the substrate-specific sequence and its traps for converging a
  host (local or remote). Remote-host pane mechanics: the swarm skill's
  tmux section.

## Sequence

1. **Survey before touching anything.** Enumerate what the host already
   carries: `~/.config/nvim`, `~/.local/opt/*` (tool runtimes), `~/.config/<dotfile-manager>/`, `~/.local/bin` links, rc files and
   their markers, `~/.hermes/skills` count. A lived-in host is a first switch; a bare host is a
   fresh install. The survey decides which conflicts to expect and gives the
   parity-proof baseline.
2. **Machine capture.** `workstation init` (whiptail; non-TTY contexts:
   write `hosts/local/machine.json` + `hosts/local/peers.nix` directly in
   the template's shape, including `checkout`). Verify the rebuild key is live: `nix eval --raw
   "git+file://$PWD?rev=$(git rev-parse HEAD)#homeConfigurations.\"<user>@<host>\".config.home.username"
   --override-input machine-files path:$PWD/hosts/local`.
3. **Build the activation package**: `nix build --no-link
   '.#homeConfigurations.<key>.activationPackage'` — this uses the flake's
   own pinned home-manager; never hand a user a bare `home-manager` CLI verb.
4. **Run activate and treat the conflict list as the first switch map.** Every
   `Existing file … is in the way` line is a foreign or hand-placed payload file
   the substrate now owns. Files reported `will be skipped since they are the
   same` are the PARITY PROOF (byte-identical old payload). Collect the full
   list (the first run may be truncated — re-run activate; it is idempotent).
5. **Relocate conflicting paths to a preserve dir**
   (`~/workstation-aside-<date>/<same-relative-path>`, mkdir -p the
   parents, `mv`) — never rm on first pass; reversibility costs nothing.
   Distinguish superseded payload (drop candidate) from the operator's own
   tools (leave untouched).
6. **Re-run activate** until green. Expect activation-hook noise on the
   first pass (remove tombstones hitting directories, deferred ensures) —
   capture each, fix the cause, never hand-edit generated state.
   Conflicts arrive in WAVES: the activation aborts at the first conflict
   list and clearing it only exposes the next set (shells, then the nvim
   internals surface on the following pass). Loop clear → activate until
   green, capturing the full list each wave (`grep 'is in the way'` off
   the pane) and relocating it before the next attempt — a single
   clear-and-run never converges a lived-in host.
7. **Byte-diff the parity proof**: `diff -rq <preserve>/<path> <new path>`
   for the payload trees the operator cares about (nvim, tmux). Only
   intentional deltas should appear (a landed feature the old payload
   predated). Any unexpected byte delta is a regression to root-cause before
   declaring the first switch good.
8. **Consumer smokes, not fingerprints**: `nvim --headless +qa` exit 0 (with
   language modules composed — the VM/container personas declare none, so a
   headless boot with the real language set is the only smoke that catches
   generated-profile defects), theme tokens resolve, the shell fragments
   source in a fresh interactive shell, hermes launcher `--version`, skills
   count, and any pre-existing host services verified untouched.
9. **Stale leftovers** (stray tool trees, stale `.local/bin`
   links): drop only on explicit operator consent, naming the exact list —
   check every link with `readlink -f` first; dangling links into dropped
   trees are safe removes, links to the operator's own binaries are not.
   After the drop, some paths are RECREATED by the substrate's own staging
   (the agent runtime tree) — re-list before declaring leftovers.

## The one-liner chain (install.sh runs and re-runs)

- Fresh install: the script ensures nix, clones, and chains init — and it
  sources the nix daemon profile itself, but that source cannot cross into
  the operator's already-open interactive shell. When a pane session spans
  the nix install, source the profile in that shell before re-running init
  (`nix: command not found` from the shim means the shell predates the
  install, not a broken install).
- Update path (checkout exists): `hosts/local/` is gitignored, so the
  checkout is clean and install.sh pulls plainly; init keeps the
  operator's captured fields. A checkout left half-merged by an earlier
  failed run (`git status` shows `DU`/`UU`, a leftover stash) is moved
  aside with `mv` and the one-liner re-run fresh — never untangle it in
  place.
- Survey a lived-in linux host before the one-liner: distro (`/etc/os-release`),
  nix variant, an existing checkout and its `git status`/`git stash list`,
  which package owns the daemon (`systemctl cat tailscaled` + the package
  manager query), and whether sudo needs a password. A foreign tailscale
  package is expected: the provision stops naming it and the switch still
  completes.
- A fleet choice made in an init whose switch FAILED is lost (the join runs
  after the switch): once the switch succeeds, run `workstation fleet`,
  pick the same choice, and confirm the pairing on the far side's fleet log
  (`journalctl --user -u workstation-fleet`). Offline members are simply
  not counted; they pair when they next apply.
- Convergence verification battery, after the applied receipt: the
  activate's real rc (never a grep chain), `nvim --headless +qa` exit 0,
  `languages/profile.lua` present, the tools resolving from the nix
  profile, and `systemctl is-active tailscaled` on legs that provision it.
- **The convergence proof is a store-path equality**, fresh, per host,
  against the SAME ref the shim builds: `ref="git+file://$PWD?rev=$(git rev-parse HEAD)"`,
  `ov="--override-input machine-files path:$PWD/hosts/local"`;
  `nix eval --raw "$ref#homeConfigurations.\"<key>\".activationPackage.outPath" $ov`
  == `readlink -f ~/.local/state/home-manager/gcroots/current-home`
  (linux home leg); on darwin
  `"$ref#darwinConfigurations.\"<key>\".config.system.build.toplevel.outPath" $ov`
  == `readlink /run/current-system`. Take `<key>` from `attrNames` of the
  same ref. Uncommitted payload edits are outside the build by design; the
  machine files are inside it. A docs-only commit does not drift a host;
  any deployed change does — apply on all hosts and re-prove.

## A previous system-daemon install

The substrate provisions its own daemon unit (tailscaled:
`workstation-tailscaled`, modules/network) and never removes another
install — a package, snap or foreign unit stops the provision, named.
Removing a host's previous install is an operator-run, out-of-repo one-off
(a runner in tmux on the target, never repo code). Rules for that runner:

| Step | Rule (why) |
| --- | --- |
| Survey | package manager (dpkg/pacman/rpm/snap), repo source + keyring, foreign `/etc/systemd/system/<unit>`, state dir, the CURRENT daemon version — and how the operator is connected (`tmux list-clients` → parent `login -h <ip>`) |
| Version | never downgrade a daemon under newer state — take it from the foundation (unstable) input when the pinned set trails |
| State | copy it to `/var/lib/workstation/<name>-aside-<stamp>/` and keep the SAME state path in the new unit — the node keeps identity, IP, prefs, login |
| Removal | package REMOVE, never purge (the tailscale deb purge runs `rm -rf /var/lib/tailscale`); stop+disable first (pacman does not stop on removal) |
| Mask | the deb postrm on remove symlinks the unit to `/dev/null` — move it aside and write the substrate unit in its place, then `daemon-reload` |
| Sources | repo list + keyring move aside so the distro never reinstalls it |
| Root (repo side) | answer a converged host without root (world-readable checks), detect a conflicting install before any sudo re-exec; re-exec under sudo only on change; HM activation PATH lacks host tools — append `/usr/sbin:/usr/bin:/sbin:/bin` |
| Transport | the operator often arrives over Tailscale SSH: the swap drops the session (tmux survives) — confirm a public sshd fallback first |

Test the stop path on a live host without risk: prepend a fake
`dpkg-query` printing `install ok installed` to PATH and run the composed
script (`TAILSCALE_PKG=<gcroot target>` + the script) with `on` — it must
exit nonzero naming the package before touching anything, and the running
daemon stays active. Prove a full runner in a systemd container before a host: `ubuntu:24.04` + systemd
as init (`--privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw
--tmpfs /run`), `/nix/store` bind-mounted read-only, the vendor's real
install script as the previous install — START that daemon first so state
exists (the vendor script may leave it inactive in a container), then
on / on-again-without-root / restart / off, asserting state hash equality.

## Traps exercised

- **The generated lua-module trap**: `lib.generators.toLua` emits a bare
  table literal; written verbatim as a module file it is an INVALID lua
  chunk (nvim dies E5113 on require). A generated lua module must be
  `"return " + generator-output + ";"`. Only a host that composes the
  surface catches it — a persona with no languages never will.
- **Version floors move with the payload**: a move that swaps the
  provider of a tool (download pin → nixpkgs) must floor the version at the
  dropped pin's line (assert `lib.versionAtLeast` in the owning module and
  supply the newer build through the overlay) — the pinned 25.05 set's
  neovim is OLDER than the removed binary pin, and the regression only
  shows in `nvim --version` after the switch.
- **HM conflicts are the inventory, not the enemy**: the conflict list is
  the complete map of what the host carries; skipping the survey and
  relying on it works, but only the survey tells you which conflicts are
  operator-owned (do not relocate) versus superseded payload (relocate).
- **The first activation bypasses the receipt**: `switch.log` gets its
  first line from the switch driver, which only exists after a generation
  is staged — a bare activationPackage run writes no receipt. Expected;
  the next `workstation apply` starts the ledger.
- **Test fixtures that assume an uncaptured machine**: gates/tests reading
  `hosts/local/machine.json` for the TEMPLATE sentinel must own their own fixture
  file (and a template `peers.nix` beside it — init seeds both) — on a converged host the live checkout's machine is captured and
  the refusal path never fires. Fixture checkouts under a scratch dir may sit
  inside some outer git repo: the shim only takes the `?rev=` path when the
  dir IS the git toplevel.
