# Hermes A2A in the agent domain — mechanics and pitfalls

The surface: `programs.hermes.a2a` (modules/agent/agent.nix), the
activation `converge-hermes-a2a` (files/a2a-converge.sh), `workstation
peers` (files/a2a-peers.sh), the fleet (files/a2a-fleet.sh, `workstation
fleet`, the member service), the token store (files/a2a-token.sh), all
built in modules/agent/packages.nix and exported as flake `packages`; the
machine-local `hosts/peers.nix` and the identity's `fleet` field.
docs/capabilities.md (agent) is the contract; this file carries what cost
debug cycles.

## The hermes CLI as an activation writer

- `~/.hermes/config.yaml` and `.env` are hot: write only through hermes'
  own writers, only declared keys, only on drift, verified by re-read.
- `hermes config set KEY v`: UPPER_SNAKE keys route to `.env`; dotted keys
  to config.yaml (`gateway.platforms.*` canonicalizes to root `platforms`).
  Unknown keys (`a2a_agents.*`, `a2a.trusted_peers`) need `--force` or the
  write is refused/noticed. A flow-mapping/JSON value sets a whole dict.
- `hermes config get <key>` EXPANDS `${VAR}` references — to assert that a
  config entry carries the reference (not the value), grep config.yaml.
- Each CLI call costs ~1.5–2 s: read with yq-go (`yq -o json -I=0
  '(<path>) | sort_keys(..)'`, bracket paths `.["a2a_agents"]["my-node"]`
  for hyphenated keys; never `//` — it treats `false` as absent) and call
  the CLI only on drift. A no-op apply makes zero hermes calls.
- Building a JSON list from newline names: `yq -p yaml` folds the lines
  into ONE scalar. Validate each name against the DNS-label grammar, then
  `"[$(printf '"%s",' $names | sed 's/,$//')]"` is safe.
- HM's activation PATH has no systemctl/launchctl: append the system dirs
  before `hermes gateway restart`. Activation runs `set -eu -o pipefail` —
  wrap the converge in `if …; then :; else echo deferred; fi`.
- Hermes calls inside a `while read … done <file` loop eat the loop's
  stdin: `</dev/null` on every CLI call.
- `hermes gateway list` marks the HERMES_HOME's row `(current) — PID n`;
  `gateway status` exits 0 either way (useless as a probe). From a scratch
  HERMES_HOME no row is `(current)` — scratch converges never restart the
  host gateway. NEVER call `hermes gateway restart` with a scratch
  HERMES_HOME: its service resolution can land on the live unit.
- `gateway restart` refuses only the gateway process itself; a descendant
  (an agent session's shell running `workstation apply`) is not refused and
  the restart takes it down. Guard: ancestor walk to the gateway pid OR
  identical `/proc/<pid>/cgroup` → defer with a receipt. Tests of the
  "running elsewhere" branch need a pid in a DIFFERENT cgroup (a sibling
  `sleep` shares the tool's tmux scope and reads as inside).
- Runtime writers (the fleet) and the converge share keys: the converge
  must compute `a2a.trusted_peers` as declared peers UNION the runtime
  roster (`~/.local/state/workstation/fleet.members`), or the next apply
  silently drops every runtime-paired member.

## Secrets through hermes (pairing tokens)

- ONE writer for tokens: `workstation-a2a-token set|drop <node>`, value on
  stdin (`printf '%s' "$t" | …` — printf is a builtin, never argv). Every
  pairing path (peers hub, fleet join, fleet handler) calls it; never embed
  a second python writer.
- Token values: never argv, never a file, never a log. HTTP auth headers
  via `printf 'header = "Authorization: Bearer %s"' "$t" | curl -K - …`.
- `hermes_bootstrap` RE-EXECUTES the interpreter on every import (same
  pid). A value popped from `os.environ` before `import hermes_bootstrap`
  is gone in the re-executed run — the writer stored EMPTY tokens. Pop
  right after the import; refuse an empty value; prepare a fresh data root
  with a secret-free call first (its first bootstrap installs deps).
- Error output names the exception class only — a message can carry the
  value. Debug with a throwaway value in a scratch copy, never the real one.

## The pairing protocol (peers hub, manual)

- Initiator: one-shot `socat TCP-LISTEN:<A2A port+1>,bind=<own tailnet
  IPv4>,fork,range=<peer IPv4>/32 EXEC:"<self> --pair-handler"`, token in
  socat's ENVIRONMENT; `/offer` answers `workstation-pair v1 from=X to=Y`,
  `/token` serves once then 410. Socat address strings break on `,`/`:` in
  SYSTEM commands — dispatch the handler as a mode of the script itself.
- Responder: the scan probes every online node's `/offer`; Accept fetches
  `/token` (`$(curl …)`, never a file), stores both ends' keys.
- Both ends leave `~/.local/state/workstation/hermes-a2a.restart`; the
  converge counts it as a change (tokens are invisible to its reads).
- Port map: A2A 9900, the peers offer A2A+1 (9901), the fleet service
  9902. Grep for DERIVED ports (`port + 1`) before picking a new default.

## The fleet (automatic pairing)

- Trust = same tailscale user: the handler resolves the caller with
  `tailscale whois --json $SOCAT_PEERADDR` and compares `.Node.User` with
  `tailscale status --json` `.Self.UserID` (numbers; `tostring` both). Node
  name = `.Node.Name | split(".")[0]`, validated as a DNS label.
- Discovery: `GET /fleet` → `workstation-fleet v1 member=<node>`; the joiner
  probes online peers of its own user, `POST /join` gets a fresh token, and
  checks the reply names the member it probed.
- Service loop shape (systemd user unit / launchd agent, same program):
  run the listener in the BACKGROUND and `wait` it, `sleep N & wait $!`,
  and `trap 'kill "$child"; exit 0' TERM INT`. A foreground child or
  foreground `sleep` defers the TERM until it returns, and killing the loop
  orphans a socat that keeps the port bound.
- Handler work after the response: socat kills the EXEC child once the
  caller hangs up, so anything after `respond` (gateway restart) must run
  detached: `( trap '' TERM HUP PIPE; restart ) </dev/null >/dev/null &`.
  Release the lock BEFORE responding, never after.
- `mkdir` locks: treat a lockdir older than ~2 min as stale (`find
  "$lockdir" -maxdepth 0 -mmin +2`) — a killed holder blocks every later
  join otherwise. findutils must be in runtimeInputs.
- The fleet choice lives in the identity (`fleet = "member"|"standalone"`,
  absent = member) so existing hosts keep working; the legs map standalone
  to `a2a.enable = false`. On the linux home leg, turning the fleet on also
  selects the `network` domain (tailscale is selection-gated there).

## Deploying on live hosts (the server and darwin legs, exercised)

- The shim's `switch_flake()` hands a writable checkout to the driver
  (`WORKSTATION_SWITCH_FLAKE`) for `apply` and every verb's apply offer —
  a verb's machine-file edit lands in the same switch. A verb that
  switches itself must export it the same way (and pass it through `sudo
  env` on darwin).
- macOS leg: `sudo env NIX_CONFIG="extra-experimental-features =
  nix-command flakes" "$(command -v workstation)" apply --system` (sudo per
  apply; the operator types the password in the pane). Check `command -v
  workstation` resolves to the substrate shim first — an engine-era
  `~/.local/bin/workstation` shadows it (move it to a dated backup dir).
- macOS has no `timeout(1)` — don't use it in pane commands.
- Testing a branch on a host whose checkout carries uncommitted machine
  files (identity, peers, selections, evaluation-only edits): `tar -cf` them
  to scratch, `git checkout -- <files>`, `git checkout --detach
  origin/<branch>` (a branch checked out in another worktree cannot be
  checked out again), `tar -xf` back, verify `git status`.
- The activation PATH has no git: every switch prints `hermes checkout
  ensure deferred — git unavailable on PATH` — pre-existing, harmless.
- A fleet join restarts the gateway on BOTH ends; `hermes gateway restart`
  exits and systemd restarts it (journal 'Scheduled restart job, restart
  counter is at N' — a lifetime counter, not a crash loop). Checks right
  after a join race that restart: re-probe the cards before calling a
  failure.
- A node that comes back as a NEW tailnet node (new IP) keeps `A2A_HOST`
  on the old address until another apply re-converges it — order the
  sequence login → apply → join.
- Proving both directions: the a2a client toolset exists only on
  `toolsetPlatforms` (`cli` by default), so a session the far agent runs
  for an INBOUND A2A call cannot call onward — a relay prompt always fails.
  Run the reverse leg as `hermes chat -q '…a2a…' --oneshot` on the far host
  (its pane) and prove it on the near host's `~/.hermes/a2a_audit.jsonl`
  (an `inbound` row with `peer: <far node>`); unauthenticated POST → 401
  on both ends.

## Testing

- Shim dialog flows (shim-dispatch.sh): a queue whiptail stub — one answer
  per line (`yes`/`no` for `--yesno`, a tag for menus, printed to stderr),
  `--msgbox` exits 0 without consuming, an EXHAUSTED queue exits 1 (ESC) —
  an empty answer spins a menu loop forever. Assert switch counts and
  helper calls through a stub log; mutation-check one rule (make Start
  join) to prove the gate bites.
- Payload helpers: run the RAW script (writeShellApplication prepends its
  runtimeInputs and shadows stubs) with the built program's runtime PATH
  extracted from its `export PATH=` line (minus the stubbed tool); under a
  pty for dialogs: `script -qec "…" /dev/null`.
- Several nodes on one host: X binds 127.0.0.2; Y calls from 127.0.0.1;
  a third node needs a curl stub that adds `--interface 127.0.0.3` per
  HOME, else it shares Y's source address and X identifies it as Y.
  Separate HOMEs, the pinned python symlinked in, `HERMES_ENGINE_CHECKOUT`
  at the real checkout, a tailscale stub serving per-HOME status/whois JSON.
- Refusal tests must reach the server: when the client also filters (the
  joiner skips other users' nodes), make the refused node's own view admit
  the target, or the test passes on the client filter and the server check
  never runs.
- Background the service under test DIRECTLY (`env -i … script serve &`)
  so `$!` is the loop itself; assert teardown leaves no process. Clean up
  leaked listeners by pid from `ps` (patterns assembled at runtime), and
  re-check after the loop's sleep interval — a dying loop respawns once.
- The live proof: converge a scratch home, `hermes gateway run` there
  (env -i), card on the real tailnet IP, no token → 401, wrong → 401, the
  paired token → 200 JSON-RPC `task not found`; kill only that pid.
