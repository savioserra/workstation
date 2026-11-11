# Cutting a macOS host over (the darwin leg)

The darwin leg's first switch differs from the linux/home-plane flow: the
operator surface stays `workstation init`, but the plane behind it is
nix-darwin, and the bootstrap has its own ordering.

## Sequence

1. **Survey**: `sw_vers -productVersion`, `uname -m` (aarch64-darwin),
   `command -v nix`, `sudo -n true` (passwordless or not). A foreign
   host carries the same payload shapes as linux but NO nix — the engine
   never needed it there.
2. **Install nix** (the one hard prerequisite): the Determinate installer
   escalates via sudo — over ssh the OPERATOR types the password; never
   handle credentials. After install, source
   `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` in the same
   shell (a fresh shell also works).
3. **Clone** the repo (`~/lazyvim`), then `./bin/workstation init` —
   captures the identity (`host` = the mac's hostname, `user` = the mac
   user, `home` = `/Users/<user>`) and chains the first switch.
4. **The first switch is the darwin plane** — build
   `github:LnL7/nix-darwin#darwin-rebuild` as the user, then escalate the
   activation:
   `sudo env NIX_CONFIG="extra-experimental-features = nix-command flakes" <drv>/bin/darwin-rebuild switch --flake <checkout>#<key>`.
   System activation is root-only; sudo's env_reset drops PATH and
   NIX_CONFIG, so pass NIX_CONFIG explicitly through `sudo env`.
5. **Subsequent switches** use the system's own darwin-rebuild
   (`/run/current-system/sw/bin/darwin-rebuild`) via `workstation apply` —
   the bootstrap's registry ref (unpinned master) is skew-safe only because
   the first switch replaces it with the flake-pinned one.

## Traps exercised

- **Select the leg by `uname`, never by CLI presence.** A fresh mac has no
  `darwin-rebuild`, so gating the darwin path on `command -v
  darwin-rebuild` falls through to the home lane.
- **The machine-derived key is NOT host-scoped.** The homeConfiguration
  key (`${user}@${host}`) derives from `hosts/local/machine.json`, and on a mac
  clone that same string matches the LINUX leg's home configuration —
  building it on aarch64-darwin dies with `Reason: platform mismatch,
  Required system: x86_64-linux` mid-closure (the `hm_.bash_profile.drv`
  derivations are the tell). The mac's first switch goes through
  `darwinConfigurations.<key>.system`, never a homeConfiguration.
- **The nix-darwin flake ref is `LnL7/nix-darwin`.** `nix run
  nix-darwin/nix-darwin#...` resolves as owner/repo and 422s on the GitHub
  API ('No commit found for SHA: nix-darwin').
- **`nix build` then `nix eval` is two dirty-tree evaluations** — build
  with `--print-out-paths` and activate the printed path (the same
  single-invocation rule as the linux leg).
- **Interactive sudo over ssh**: every system-plane step prompts; the
  operator stays at the pane and types. Poll the pane between steps; do
  not batch a sudo prompt with other commands.

## The lived-in home gauntlet (first switch on a lived-in mac)

A lived-in mac fails the first darwin switch in a fixed order of gates.
Each fix below is a real landed change — do not skip ahead: fix, re-run,
read the NEXT gate.

1. **Determinate vs nix-darwin Nix management.** A Determinate-installed
   mac dies at eval: nix-darwin's native Nix management conflicts with the
   Determinate daemon, and the fix is `nix.enable = false;` — set it inside
   the darwin system's modules (a record-level placement next to the leg's
   return value is INERT; nix-darwin only reads it from the module config).
2. **`/etc/zshenv` abort.** The Determinate installer writes its own
   `/etc/zshenv` (sourcing the nix daemon profile); nix-darwin aborts on
   the unrecognized content. The remedy is its documented rename
   (`mv /etc/zshenv /etc/zshenv.before-nix-darwin`), but read the file
   first: after the switch, zsh may does not source the nix profile (the
   substrate does not manage /etc) — restore the sourcing block manually
   if `nix` leaves PATH in zsh. /etc stays host-owned.
3. **brew `--cleanup` disabled.** brew 7.0.11 removed the `--cleanup`
   switch; nix-darwin's homebrew `onActivation.cleanup = "zap"` fails the
   activation. Keep `onActivation` at its defaults (no cleanup, no
   autoUpdate/upgrade — those fight the pinned brew; see 'Homebrew as a
   managed dependency').
4. **Conflicting home files abort the HM activation.** A lived-in home
   carries deployed nvim payload copies and rc files in the way of the new
   generation. The home plane sets `home.backupFileExtension = "hm-backup"`
   on every leg (first switches move files aside instead of aborting); a
   leg-specific `home-manager.backupFileExtension` is redundant. For an
   lived-in home, also relocate the conflicting files to a preserve dir — do BOTH passes in
   the pane with error-to-relocate loops (`grep 'in the way'`), and grep
   BOTH abort shapes ('Existing file' AND 'Is a directory'): directory
   conflicts (the old plugin checkouts, fonts) log in the cmp form that a
   file-only extraction misses.
5. **The PATH shadowing follow-up.** After a green switch, the
   old engine's `~/.local/bin` links still shadow the substrate's tools
   (`nvim` 0.12.4 vs 0.12.6, mise/eza/starship from `~/.local/opt`): the
   engine-era cleanup pass (drop the old `~/.local/bin` links and
   `~/.local/opt` trees, preserving the operator's own tools) is what
   actually puts the substrate's versions on PATH. Verify with
   `nvim --version` and `which <tool>` after the cleanup, not before.

## Repo state on a converging host

- `hosts/local/` is gitignored, so pulls on a converged mac are clean and
  re-running `./bin/workstation init` keeps captured fields and settings.
  A checkout from before a machine-file move: back the files up,
  `git checkout --` the tracked copies, pull, copy them into the new place
  (never `git stash` — the stash ref is shared across worktrees).
- A mac whose staged `workstation-switch` predates a launcher-contract
  change needs one direct `sudo darwin-rebuild switch --flake <ref>#<key>
  --override-input machine-files path:$PWD/hosts/local` (SKILL.md, driver
  contract rule); every later switch is `workstation apply --system`.
- Pulling main mid-landing (a card worker is committing a restructure)
  leaves the checkout in a state whose eval fails with phantom paths —
  check the card status and re-pull only after the landing card completes.
- Driving the mac over Tailscale SSH: each new session may require the
  browser 'additional check'; the link expires within minutes. Trigger the
  ssh only when the operator says they are at the browser, hand them the
  fresh link, and read the pane once after.
- When the operator says 'authenticated', READ THE PANE (with scrollback,
  `capture-pane -S -60`) before sending anything: the session may already
  be open, or the host may have rebooted ('System going down'). After a
  disconnect, `tailscale ping -c 1 <host>` from the other host before
  reconnecting.
- An unexpected host-key prompt (sshd answering instead of Tailscale SSH):
  verify the offered fingerprint against the coordination server before
  accepting — `tailscale status --json` → the peer's `sshHostKeys`, each
  piped through `ssh-keygen -lf -`. Capture the pane IMMEDIATELY before
  typing the answer: a prompt already answered turns `yes` into the `yes`
  command (an endless 'y' stream — Ctrl-C at once).
- Delivering files to the mac without an ssh key: serve a scratch dir
  (only the files needed) with `python3 -m http.server <port> --bind
  <the server leg tailnet IP>` as a background process, `curl -fsS` from the mac pane,
  then kill the server right after the fetch.

## Homebrew as a managed dependency

nixpkgs has no Homebrew package. The mac leg imports
`nix-homebrew.darwinModules.nix-homebrew` (flake input
`github:zhaofengli/nix-homebrew`; its `brew-src` input pins the brew
release in `flake.lock`) with `enable = true; user = machine.user;
autoMigrate = true;` and keeps `homebrew.enable = true` for declared
formulas/casks. `autoMigrate` takes over an existing install (it deletes
brew's own git repos, keeps installed packages); a fresh mac gets a new
install. Moving the brew pin is `nix flake update nix-homebrew`. Eval
proof on the linux box: `darwinConfigurations."<key>".config.nix-homebrew`
→ `{ enable, user, autoMigrate, package.version }` with the mac machine
files overridden in.

## Replacing Tailscale.app with the substrate daemon (operator-run)

The darwin leg sets `workstation.enable = true`; without it the shared
system module is inert and `services.tailscale` never runs. The repo only
enables `services.tailscale`; removing an existing Tailscale.app, its CLI
shim or a brew formula is a host-local one-off — an out-of-repo runner,
never a system activation hook. A stopped removal leaves the app serving.

1. Deliver one runner and start it in tmux ON the mac (`tmux new-session
   -s first switch 'sh runner | tee ~/log'`): the sysext removal drops the
   tailnet the ssh session rides. Serve the runner from the other host over
   the tailnet (a temporary `python3 -m http.server` bound to its tailnet
   IP; stop it after) when no ssh key exists. Inside: `sudo -v` once plus a
   keepalive loop, GUI steps through `sudo launchctl asuser <uid> sudo -u
   <user> open|osascript`.
2. The switch deactivates the sysext as the CONSOLE user
   (`/Applications/Tailscale.app/Contents/MacOS/tailscale configure sysext
   deactivate`, bounded with `perl -e 'alarm shift; exec @ARGV' 300`):
   macOS shows an approval dialog the operator must answer at the Mac.
3. The app's node identity cannot move: the nix daemon is a NEW node.
   Remove the old machine in the admin console BEFORE authorizing
   `sudo tailscale up --hostname=<name>`, or it registers as `<name>-1` and
   every peer reference breaks.
4. Then a second `apply --system` (A2A_HOST re-binds to the new IP), then
   the fleet join.
5. Verify from the other host while the pane is down: `tailscale status`
   (same name, new IP, same user), the fleet marker and A2A card on the new
   node, the audit log. `systemextensionsctl list` shows the old extensions
   'terminated waiting to uninstall on reboot' — normal.
