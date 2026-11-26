# Workstation capability and lifecycle reference

Declared state is native nix/home-manager: one module per capability domain
under `modules/<domain>/`, module and payload bytes co-located. Reads are
`nix eval` over `workstation.report.<verb>`. Nothing here describes a
surface before its owning commit lands it.

## Dependency direction

```text
flake.nix
  -> nix/lib/machine.nix  (hosts/local/machine.json: identity + settings)
  -> nix/modules          (workstation-home imports modules/; workstation-system, host)
  -> modules/default.nix  (the domain and member modules, listed)
  -> nix/report.nix       (workstation.report.<verb>: one home eval)
  -> nix/lib/switch.nix  (the composed write plane: verb scaffold + routine registry, switch.log receipt)
  -> hosts/{linux,mac}    (the system legs)

bin/workstation (POSIX sh: flake resolution, verb dispatch)
  reads:  nix eval --json <flake>#workstation.report.<verb>
  select: workstation add|remove <path>  (hosts/local/machine.json settings via jq,
          validated against workstation.report.selectable)
  writes: workstation apply  (execs the staged switch driver)
```

- Reads are pure `nix eval`; mutation is `workstation apply`.
- `bin/workstation` is the sole entry point.
- `modules/**/*.lua` are data payload files, read as bytes, never executed.

## Capability selection

The machine file `hosts/local/machine.json` (gitignored, seeded from
`hosts/template/`) carries the identity and `settings`, a home-manager
option tree applied as a module.

```json
{
  "host": "<host>",
  "user": "<user>",
  "home": "<home>",
  "system": "x86_64-linux",
  "settings": {
    "workstation": {
      "network": { "enable": true },
      "languages": { "go": { "enable": true } }
    }
  }
}
```

| Rule | Mechanism |
| --- | --- |
| Paths | `<domain>` or `<domain>/<member>`: `workstation.<domain>.enable`, `workstation.<domain>.<member>.enable` |
| Validation | the module system: unknown option and wrong type fail the eval |
| Defaults | each enable option's default: domains on, `network` and language members off |
| Members | deploy iff `domain.enable && member.enable`; `add <member>` turns a disabled domain on |
| Baseline | `foundation` has no enable option |
| Reads | `selected` serves `workstation.report.selections`: per path `on`/`off`/`baseline` and the option description |

## Module boundaries

| Module | Contract |
| --- | --- |
| `bin/workstation` | Launcher shim: flake resolution order, verb dispatch, exit codes (dispatch gate: `.github/scripts/shim-dispatch.sh`) |
| `nix/lib/machine.nix` | The machine file: identity, the flake keys (`homeKey`, `systemKey`), `settings` and `workstation.machine` as home modules |
| `modules/default.nix` | The capability module list |
| `modules/<domain>/<domain>.nix` | The domain's options and declarations, gated on `workstation.<domain>.enable` (members also on their own flag) |
| `nix/report.nix` | The read verbs from one home eval: rows from the option tree, attribution from `definitionsWithLocations` |
| `nix/lib/capability.nix` | The module helpers, imported by relative path: `capability` (the enable option + its gate over every enclosing enable), `whenOn` (a contribution guarded by the owning domain's enable), `isOn` (every enable on a path), `shellInit`; the payload helpers ride along |
| `nix/lib/payload.nix` | The payload helpers, free of the module system: `script`, `overlayTree` |
| `nix/lib/license.nix` | The secrets domain's unfree acceptance (the 1Password CLI): one predicate, imported by every composition root |
| `modules/agent/agent.nix` | The agent domain's hot-home surfaces: managed skill leaves, the checkout ensure, version-matched skill provisions |
| `modules/<domain>/` payload dirs | Payload assets (`files/`, verify scripts), co-located with the declaring module |
| `modules/theme/themes/*.nix` | The themes (`dark`, `light`): appearance + a `#rrggbb` palette per role — nix data typed by `workstation.theme.themes` |

## Declaration contract

- One native nix module per domain, imported by `workstation-home.nix`
  (system-plane toolchains ride `workstation-system.nix` / `home.packages`).
  The module import IS the registration; duplicate options fail the eval.
- Module shape: `ws.capability [ "<domain>" "<member>" ] { description; default; options; config; }`
  (`ws = import <rel>/nix/lib/capability.nix { inherit config lib pkgs; }`):
  the enable option at the path, `config` gated on every enclosing enable;
  a contribution to another domain's option rides `ws.whenOn "<domain>" { … }`.
- Payload bytes live beside the module and are copied into the store at
  eval.
- A capability declares, natively:
  - **file/symlink surfaces** — `home.file` entries with store-path sources
    (intra-home links through `mkOutOfStoreSymlink`);
  - **tools** — packages of the one nixpkgs input; the remaining pins
    declare inline: herdr's `fetchurl`, the hermes
    checkout as the flake's `hermes-agent` input;
  - **dir claims** — a store tree linked at a home target; overlapping
    targets compose into one derivation;
  - **shell init** — upstream `programs.bash` / `programs.zsh` /
    `programs.starship` / `programs.eza` / `programs.direnv`; ordered
    lines ride `lib.mkOrder` on `initExtra` / `initContent`, env rides
    `home.sessionVariables` (`.profile`, `.zshenv`);
  - **activation scripts** — hot-home and mutation surfaces, sequenced with
    `lib.hm.sequence`;
  - **the switch driver** — the one system-ordered surface: its tail writes
    the receipt; the theme activation seeds the pick and reloads the
    theme consumers;
  - **the routine registry** — `workstation.routines.<event>`
    (after-apply, after-rollback, after-update): module-registered shell
    routines the driver runs at the event, after the receipt; a failed
    routine reports and never fails the switch.
- No inter-capability ordering graph exists: store closure has no apply
  order. The only ordered surfaces are the ones above.

## Capability graph

Declared data on each module (its domain), consumed by the report:

```text
base       foundation
fonts      fonts
languages  languages/elixir, languages/go, languages/node, languages/typescript (member capabilities)
editor     nvim (+ languages: typescript, elixir declare editor entries)
terminal   terminal, terminal/zellij (member capability)
theme      theme
agent      agent, herdr
secrets    secrets
```

Domain order is lifecycle order; an unpinned domain name renders appended
and sorted, never hidden.

## Capabilities

### `foundation`
- bash and zsh (`programs.bash`, `programs.zsh`), `~/.local/bin` on
  PATH (`home.sessionPath`), direnv + nix-direnv (the bash hook after the
  prompt init).
- `workstation.foundation.shell.extras` (types.lines, default ""): the
  operator's per-machine rc lines (`settings.workstation.foundation.shell.extras`
  in the machine file), the last lines of `.bashrc` and `.zshrc`.
- Tools, all nixpkgs: fd, ripgrep, lazygit, mise, newt (whiptail, the
  shim's install-time UI).
- The tailscale transport (`workstation.network.enable`;
  `services.tailscale` on the system legs through `modules/network/system.nix`; on standalone linux the
  `workstation-tailscaled` activation: the substrate's systemd unit; a
  package, snap or foreign unit already owning tailscaled stops the
  provision, named; off retracts the unit only). The
  machine file's `workstation.network.enable = false` turns the transport off.
- Hosts: all.

### `fonts`
- JetBrainsMono Nerd Font from nixpkgs (`pkgs.nerd-fonts.jetbrains-mono`);
  fontconfig enabled.
- Targets: linux `.local/share/fonts/JetBrainsMonoNerdFont`, darwin
  `Library/Fonts/JetBrainsMonoNerdFont`.
- Verify: the deployed font dir (the container E2E asserts it). Hosts: all.

### `languages`
- The domain owns the mise plane: the global config
  (`~/.config/mise/config.toml`, a read-only store link — the enabled
  members' pins compose its `[tools]` table), the cd activation in
  bash/zsh (after the direnv hook, before the operator extras) and the
  `mise install` activation (best-effort; mise's auto-install on use is
  the backstop).
- Toolchains install from the pinned registry versions into
  `~/.local/share/mise`; project-level pins belong to each repo's
  `.mise.toml`/`.tool-versions`.
- Prebuilt toolchain binaries need a glibc host; the linux system leg
  enables nix-ld for them.
- Verify: the config pins and the installed tools (the container E2E
  asserts both). Hosts: all.

### `node`
- mise pin `node = "24.22.2"` in the global config; `.node-version`
  derives from the pin (one source).
- Verify: the config pin, the installed tool and `.node-version` (the
  container E2E asserts all three). Hosts: all.

### `agent`
- The hermes runtime pin: the flake's `hermes-agent` input (fetchGit rev,
  surfaced as `outputs.hermesAgentPin` → `programs.hermes.pin`); the
  checkout `~/.hermes/hermes-agent` ensured to the pin by activation —
  clone/fetch only when absent or clean-and-behind, never touching a dirty
  or runtime-advanced tree (the hot-dir law: activation mutates, the file
  plane never tracks).
- The interpreter: `pkgs.python314`, floored at the release the pinned
  rev's `pm/lock.json` carries (the eval dies loud naming both versions on
  a mismatch), claimed at `.local/opt/hermes/python`.
- The launcher: `programs.hermes.package` at `.local/bin/hermes`; resolves
  the interpreter and checkout from `$HOME` at run time, runs the
  interpreter isolated, fails closed with a named message.
- Pane resume (inside a zellij pane): the launcher starts
  `hermes-pane-resume` beside itself; while hermes runs it reads the
  pane's terminal breadcrumb (`~/.hermes/terminal-sessions/tty-<tty>`, else
  `zellij_pane_id-<id>`; only breadcrumbs written since the launch) and keeps
  the pane's resurrect command on `~/.local/bin/hermes [--tui|--cli] --resume
  <id>` (`zellij action set-resurrect-command`), following `/new` and
  session switches; a resurrected pane reopens its conversation, the
  compression chain followed to the live tip. Outside zellij: a no-op.
- Theme (theme domain on): `~/.hermes/skins/workstation-<theme>.yaml` per
  theme from `ws.themeTokens`; the pick sets `display.skin` through
  `hermes config set` ([theme](theme.md)).
- The deployed pin manifest `.local/opt/hermes/pin.json` — the verify
  anchor.
- Skills: `programs.hermes.skills` — one store entry symlink per target
  profile (`default` → `~/.hermes/skills`; named →
  `~/.hermes/profiles/<name>/skills`). The skills parent stays hot
  (`skills_sync` seeds bundled skills; the curator archives there; a
  declared name the pinned tree bundles fails the eval). `secrets` is
  authored at `modules/agent/skills/secrets`; `workstation` (the substrate
  dev workflow + references) is authored at
  `modules/agent/skills/workstation`; `hsql` is generated from the
  harlequin derivation by `hsql --skill` at build time.
- Gateway extensions: `programs.hermes.extensions` → entry symlinks into
  `~/.hermes/plugins/<name>`.
- Verify: `modules/agent/verify/hermes.sh` — checkout at the deployed pin,
  store-symlink skills, interpreter, launcher `--version` consumer smoke;
  full-stack or exit 1. Hosts: all.
- Runtime-extended state the capability never freezes: the pm-managed
  dependency closure, the tool store (`~/.hermes/tools/…`), the gateway,
  profiles. Updates go through the pin: bump the
  `hermes-agent` rev; the interpreter floor re-derives from the new rev's
  `pm/lock.json`.

### `herdr`
- The one inline `fetchurl` pin (no nixpkgs coverage — upstream ships
  release binaries only), linked from its store derivation at
  `.local/bin/herdr`.
- Verify: fingerprint + link record. Hosts: all.

### `go`
- mise pin `go = "1.27.3"` in the global config.
- Verify: the config pin and the installed tool (the container E2E
  asserts both). Hosts: linux/macOS.

### `elixir`
- mise pins `elixir = "1.20.5-otp-28"` + `erlang = { 28.5.0.8, compile = false }`
  (elixir pinned to an otp-28 prebuilt build — 1.18.x ships none; erlang
  prebuilt platforms only, never a kerl source build).
- Verify: the config pins (the container E2E); own Mason expectations and
  the plugin module through nvim leaf helpers. Hosts: all.

### `typescript`
- mise pin `pnpm = "12.9.0"` in the global config.
- Verify: the config pin (the container E2E asserts it); own Mason/plugin
  surface. Hosts: all.

### `secrets`
- `pkgs._1password-cli` (unfree — the
  acceptance is `nix/lib/license.nix`, named and scoped); the op env
  (`workstation.secrets.envFile`, default `/etc/workstation/secrets.env`)
  sourced from the session variables.
- Verify: record + `--version` only, never account or vault state. Hosts:
  all supported.

### `nvim`
- The editor payload (`files/.config/nvim/**`) deployed by the editor
  domain's activation (`deploy-nvim-config`): managed paths overwrite,
  the paths the previous deploy managed that the tree dropped are
  pruned (the state tree's `nvim-managed.list` — a deselected
  language's plugin module leaves with its selection), operator extras
  and the runtime lazy-lock survive. The tree is deliberately not a
  `home.file` surface: the deployed copy is writable, so HM's manifest
  could only refuse a changed managed file, and HM's cleanup only
  deletes its own links. The nixpkgs neovim at
  `.local/bin/nvim` is the domain's `home.file` surface.
- The composed language profile: language capabilities declare profile
  entries as module data (`lazyvim_extras`, `plugin_module`, mason
  packages); one derivation composes them, in declared order, into
  `.config/nvim/lua/languages/profile.lua` (`lib.generators.toLua`; the
  file must `return` the table).
- `EDITOR`/`VISUAL`/`GIT_EDITOR=nvim` as `home.sessionVariables`.
- `.config/nvim/lazy-lock.json`: seeded by the activation merge script
  from the payload baseline, never byte-compared afterwards
  (runtime-extended).
- Verify: startup, locks, mason coverage, base/standard/Go behavior.
  Hosts: all.

### `theme`
- The themes (`modules/theme/themes/{dark,light}.nix`) typed by
  `workstation.theme.themes`.
- The consumer registry `workstation.theme.consumers.<name>` (`file`,
  `render`, `reload`); every theme rendered under
  `~/.local/share/workstation/themes/<name>/` with its `tokens.json`.
- The pick: `~/.local/state/workstation/theme/current`, seeded with
  `workstation.theme.default`, moved by `workstation theme <name>`
  (`workstation-theme`).
- Verify: the container E2E (rendered themes, seeded pick, switch, the
  pick across an apply). Hosts: all. [theme](theme.md)

### `terminal`
- `programs.eza` (`ls` = `eza -lh`, `home.shellAliases`), `programs.starship` + `.config/starship.toml`.
- mosh: `home.packages` (all legs), `programs.mosh.enable` (NixOS legs); the
  `mosh` wrapper's `--server` sources the remote home-manager session vars
  (`~/.nix-profile/etc/profile.d/hm-session-vars.sh`, the per-user profile's
  on NixOS/darwin: the profile PATH, `LOCALE_ARCHIVE_2_27` for non-C locales)
  and prepends `~/.nix-profile/bin`, `/etc/profiles/per-user/$USER/bin`,
  `/run/current-system/sw/bin` to PATH — an ssh command on a bash host
  sources neither. Other clients (Termius): the same `--server` string.
- btop: `home.packages` (all legs).
- Hosts: all.

### `zellij`
- The `terminal/zellij` member capability: `programs.zellij` (home-manager), `.config/zellij/config.kdl`; `pkgs.zellij` on the system legs.
- Session resurrection: `session_serialization true` — every session serialized to the cache dir on zellij's `serialization_interval` and on `zellij action save-session`, resurrectable after a quit, a crash or a reboot (`zellij attach <name>`, the session manager's `EXITED` section): tabs, pane layout and positions, each pane's cwd and command; resurrected commands wait behind zellij's `Press ENTER` banner.
- `serialize_pane_viewport false`: pane text and scrollback stay off disk.
- Keybinds: the built-in `unlock-first` preset (`keybinds preset="unlock-first"`) — sessions start locked, `Ctrl g` unlocks, then single keys enter the modes (`p` pane, `t` tab, `r` resize, `s` scroll, `o` session); every other chord stays with the programs in the panes.
- Look: `theme "dracula"` (`theme_dark "default"` beside it — a set `theme` pins the session and turns the dark/light pair off); pane frames with rounded corners, the session name hidden; startup tips off.
- Settings live in the module: zellij's settings screen writes `config.kdl`, which links into the store — changes there are for trying out (apply, never save); keep the kept ones here.
- Everything else: zellij's defaults.
- Verify: the container E2E (the managed config, `zellij setup --check`, a background session resurrectable after it ends). Hosts: linux/macOS.

## Fresh-host tools

Every tool class ships with the substrate; none stays a documented host
prerequisite. The HOW: the nixpkgs lock carries the versions and
`home.packages` puts the tools on PATH. Inline pins, by exception: herdr
(`fetchurl`), the hermes
checkout (the flake input). Every bump moves the owning row and its
consumer together. The hermes manifest (`~/.local/opt/hermes/pin.json`)
keeps its verify lane honest.

## Grain contract

- Domains and capabilities are rollup rows (capability count, file count,
  last applied generation in the header).
- File rows are the drill-down leaves; never a raw file dump at the top.
- Every file appears exactly once, under its primary capability
  (`hd(attribution)`), remaining contributors as an `also` note; entries
  without attribution land in `unattributed`.

## Validation

Fail-closed at eval:

- the machine file: unknown options and wrong types fail the module
  system (the shim validates paths before writing);
- target collisions across capabilities throw;
- envelope identities in the report are asserted unique;
- the identity gate holds personal identity to `hosts/local/`
  (gitignored).

## Lifecycle

| Phase | Owner | Responsibility |
| --- | --- | --- |
| switch / rollback | `workstation apply` / `workstation rollback` | Build the generation from the flake, activate atomically, write the receipt to `switch.log`; the flake is the resolved checkout's committed `HEAD` (`--flake`, `$WORKSTATION_FLAKE`, the enclosing checkout, `$WORKSTATION_CHECKOUT`) with its working-tree machine files; `WORKSTATION_WORKTREE=1` builds the working tree; an explicit `WORKSTATION_SWITCH_FLAKE` wins; `update` pulls the checkout from origin (fast-forward only, as the checkout's user under sudo), then switches; the lock moves with origin's commits; a dirty checkout, local commits origin lacks or a failed pull stop before touching anything |
| system switch | the driver's runner | A `--system` switch runs in a detached nohup process and survives its caller; the caller waits and exits with the switch's code; under sudo the receipts and the routines belong to the invoking user; log: `switch-driver.log` beside `switch.log` |
| `plan` / `status` / `capabilities` / `selected` | `nix eval` over `workstation.report` | Answer the declared state; mutate nothing |
| select | `workstation add <path>...` / `workstation remove <path>...` | Validate against `selectable`, set or drop the flag in `hosts/local/machine.json`, offer the apply (idempotent; the baseline refuses) |
| inquiry | `workstation init` (and `setup`, the full re-ask) | Capture the machine, offer the languages as a checklist pre-filled with the current selection |
| verify lane | `modules/agent/verify/hermes.sh` | The agent stack's consumer smoke against its recorded pins |

Reads are pure evals. The container E2E (`tests/nix`) asserts the shape
itself: the switch receipt in `switch.log`, and the home carries only
declared targets.

A switch is the one event a generation carries: the receipt line lands in
`switch.log`, and the theme consumers reload against the live pick
(`~/.local/state/workstation/theme/current`). Consumers read files or watch
the link; nothing polls.

## Payload rule

Host-specific or feature-specific payload stays under the owning
capability as data — no per-capability code hooks, no payload execution:

```text
modules/fonts/files/
modules/languages/node/files/
modules/agent/verify/
```

Anything requiring host execution is a pin derivation, an activation
script, or a verify assertion.

## Verification requirements

- Verify executable versions through the configured environment.
- Verify fonts through host registration or cache visibility.
- Verify Neovim imports by successful startup (and the composed profile).
- Verify languages with real files, parsers, and attached LSP clients.
- Verify formatters by comparing on-disk output.
- Verify the agent capability's full stack on every host, ending in the
  `hermes --version` consumer smoke — an absent or broken runtime is
  provisioning drift, never a documented state.
- Treat directory existence as supporting evidence, not final proof.
