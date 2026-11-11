# Container testing of installs

The container lanes: the committed tree's behavioral proof, and the
one-liner installer's dialog UX. Both run in throwaway containers —
fresh state per run, never a committed image.

## Lane 1 — the container E2E (the behavioral gate)

- Entry: `tests/nix/run-container.sh [log]` (CI runs it; locally requires
  docker).
- Source: a `git archive HEAD` extraction of the checkout — the committed
  tree only; uncommitted edits are not under test. Worktree gitdirs do not
  resolve in containers; the extraction lands in the scratch dir.
- Image: `nixos/nix` + a named store volume; the driver builds the e2e
  persona's home plane inside and runs the proof steps — the launcher
  shim, the nvim headless boot with the languages composed, the
  lazy-lock merge, the theme tokens, the agent and terminal planes, the
  shell init, the selection removal, the apply-driven switch and the
  receipt.
- No usable docker refuses loudly (`no docker …`) — never a degraded pass.

## Lane 2 — the installer one-liner, by hand

- `docker run -d --name ws-bare --init ubuntu:24.04 sleep infinity` —
  `--init` REQUIRED: a bare `sleep infinity` pid 1 never reaps orphans.
- Distro prereqs (measured on stock 24.04 — missing: git, curl, xz,
  unzip): `docker exec ws-bare bash -c 'apt-get update -qq && apt-get
  install -y git curl xz-utils unzip'`.
- The verbatim README one-liner with a UTF-8 locale (first converge
  downloads nix and builds the activation — long; background + notify):
  `docker exec -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 ws-bare bash -c 'curl
  -fsSL https://raw.githubusercontent.com/savioserra/workstation/main/install.sh | sh'`
- Verify with a LOGIN shell (`bash -lc`) — `docker exec bash -c` does not
  source the managed PATH additions and reports every managed tool
  missing. Smokes: `workstation --version`/`status`, nvim/tmux/btop/mosh
  versions, fd/fzf/rg on PATH, `~/.hermes/skills/*` entry symlinks.
- On an existing install the one-liner refuses and points at the
  lifecycle verbs — continuation is `workstation
  apply|update|setup`, never a re-run of the installer.

## Interactive lane: the dialogs of an unmerged branch

For dialog UX (init's captures, the languages checklist, the fleet menu)
driven by hand before merge:

1. `tmux new-window -d -t 0: -n ws-ct "docker run -it --rm --init --name
   ws-ct -e TERM=xterm-256color -e USER=root -v <worktree>:/src:ro
   nixos/nix:latest bash"` — `-t 0:` (trailing colon) picks the next free
   index; `-t 0` collides with window 0.
2. Inside: `git config --global --add safe.directory '*'`, then the pipe
   shape the user runs: `cat /src/install.sh |
   WORKSTATION_REPO=/src WORKSTATION_CHECKOUT=/root/wsN
   WORKSTATION_NO_APPLY=1 sh`. A fresh `wsN` per run — never mount a
   `.git` at the default checkout path.
3. Drive with single `tmux capture-pane` reads and `send-keys` (text,
   then `Enter` separately). Assert the written identity/selections with
   `docker exec`, then `docker rm -f` and kill the window.

## Pitfalls

- `curl … | sh` hands the SCRIPT on stdin: an installer that runs dialogs
  must reattach the terminal (`exec ./bin/workstation init </dev/tty>`
  when `[ -t 0 ]` fails and `/dev/tty` opens), and provide whiptail
  before the first switch ships it (`nix build --no-link
  --print-out-paths --inputs-from . nixpkgs#newt`, PATH-prepend).
- Minimal images lack `hostname(1)` (nixos/nix also lacks sed/awk):
  product code detects the host with POSIX `uname -n` (`${host%%.*}`);
  sed/awk absence is the image being barer than any real host — `nix
  profile install nixpkgs#gnused nixpkgs#gawk` in the container, not a
  product change.
- NEVER `docker commit` a partially-tested container and continue in the
  re-run: directories created before the commit sit in a lower overlayfs
  layer, and directory renames fail EXDEV — the true first-install
  journey always uses a FRESH container.
- docker exec inherits no locale — pass C.UTF-8 explicitly.
- Docker timezones can differ from the host; compare process start times
  with `ps -o lstart`, not wall-clock arithmetic.
