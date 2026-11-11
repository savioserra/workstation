# Nix module system: exercised pitfalls and proven idioms

Every shape here was verified by live `nix eval` against the real module system
(the pattern harness attached to the selections card) — not read from prose.
Re-run the harness when touching these surfaces.

## Proven idioms (use these)

- **Module shape rides `nix/lib/capability.nix`**: `ws = import <rel>/nix/lib/capability.nix { inherit config lib pkgs; };`
  then `ws.capability [ "<domain>" "<member>" ] { description; default; options; config; }`
  (the enable option + `config` gated on every enclosing enable) and
  `ws.whenOn "<domain>"` / `ws.whenOn [ "<domain>" "<member>" ]` for a
  contribution to another domain's option. Delivery is the relative import:
  `_module.args.ws` recurses the moment the helper shapes a module
  (`infinite recursion … while evaluating the module argument 'ws'`), and a
  specialArgs `ws` breaks every outside consumer of
  `homeManagerModules.workstation`. Helpers called inside the member file
  keep `definitionsWithLocations`/declarations on that file — the report's
  attribution holds (proven by drvPath + report equality on every leg).
- **Presets in an `attrsOf submodule` option merge per leaf**: define them
  in `config` with `lib.mapAttrsRecursive (_: lib.mkDefault) { … }`. A
  whole-value `lib.mkDefault { … }` is DROPPED entirely once any
  normal-priority definition touches that entry (exercised: one overridden
  role left every other role undefined). An option `default` for an
  attrsOf is replaced by any definition — never put presets there.
- **INI-shaped extension points**: a freeform submodule
  (`freeformType = attrsOf str` + declared options like `rank`) keyed by
  section header; render with `removeAttrs v [ "_module" "rank" ]`.
- **Default-ON enable**: `enable = lib.mkEnableOption "…" // { default = true; }`
  — `mkEnableOption` is literally `mkOption { default = false; type =
  lib.types.bool; description = "Whether to enable ${name}."; }`, so the `//`
  overrides the default attr (function application binds tighter than `//`).
  Default-OFF members use plain `mkEnableOption`.
- **Machine flags are a module**: `hosts/machine.json` `settings` is a raw
  option tree applied as `{ config = (lib.importJSON …).settings; }` — the
  module system rejects unknown flags and wrong types, so no translation layer
  or path validator in nix. The shim edits it with jq
  (`setpath(path + ["enable"]; true)`), validating paths against the report's
  `selectable` first.
- **Gating**: `config = lib.mkIf cfg.enable { … }` — every module is listed in
  `modules/default.nix` and always imported; only its definitions are
  conditional. A member gates on `domain.enable && member.enable`.
  `types.bool` merge is logical OR — multiple enable definitions never
  conflict.
- **Attribution without per-capability evals**: one eval, then
  `options.<x>.definitionsWithLocations` gives `{ file; value; }` per
  definition — map `file` to `modules/<id>/`. A `mkIf false` definition still
  appears there as `{ _type = "if"; condition = false; }` — filter it
  (`!(v._type or "" == "if" && !v.condition)`) or off capabilities report
  targets they never deploy.
- **Compliance**: `specialArgs.lib` is RESERVED for the nixpkgs library
  (nixpkgs Module System chapter, evalModules) — custom functions go in a
  differently-named specialArgs attr. Prefer none: relative paths
  (`../../bin/workstation`) over threading `self` through specialArgs — a
  `self` reference inside a module stages the whole repo into the closure.
- **`pkgs` must be named in the module header.** The module system injects
  `pkgs` lazily — only into modules whose function head mentions it. A module
  typed `{ config, lib, ... }` that then references `pkgs.mosh` fails eval
  with `undefined variable 'pkgs'` (the `...` absorbs unused arguments, it
  does not bind extra ones). Add `pkgs` to the head the moment a module gains
  a `home.packages`/`environment.systemPackages` line.
- **Plain CLI tool vs `programs.*`**: `home.packages` is the idiom for a
  stateless binary home-manager has no module for (mosh, fzf, tmux,
  lazygit) — referencing `programs.<x>` that home-manager does not ship
  fails the eval with `option does not exist`. NixOS's system-plane
  `programs.<x>.enable` is a different surface, set only when it carries
  more than the package (a service, firewall ports) — but it must live in
  the LEG file (`hosts/linux/default.nix`), never in the shared
  `nix/modules/workstation-system.nix`: the darwin eval checks every
  config attr name against declared options BEFORE mkIf conditions apply,
  so an NixOS-only option reds the darwin leg even inside `mkIf
  (!isDarwin)` (exercised: `programs.mosh` under a platform guard still
  failed the darwin eval). Home-plane `home.packages` covers every leg
  with the same one declaration.
- **Indented strings open with `''` (two apostrophes).** `'''` parses as the
  open plus a literal apostrophe starting the content — a `writeText` payload
  then carries a leading `'` into every deployed copy, and a `''';` closer is
  an escaped apostrophe plus a semicolon swallowed by the string (the file
  runs to EOF). Symptom: `unexpected EOF while looking for matching ''` from
  every shell that sources the deployed file.

## Traps (exercised — each cost a debug cycle)

- **A module with `options`/`config` keys must put every definition inside
  `config`.** `{ options = …; home.packages = …; config = mkIf … }` mixes
  module keys with plain config keys; tool packages go INSIDE the gated
  `config` block, never beside it. Any discovery layer that classifies module
  files by shape (a filesystem walk) must throw on the mixed shape — a silent
  skip drops the module's activations with no error.
- **Config keys must be declared options.** The module system rejects
  undeclared config attributes outright (`The option 'result' does not
  exist`). Every eval that SETS an option must import its declaration — a
  secondary eval (a report baseline, a test harness) that applies the machine
  settings without the domain modules breaks on the first flag the machine
  sets. Prove a new enable with the read verbs (`nix eval
  .#workstation.report.status`, `workstation selected`) on a host checkout
  that sets it, not on the template.
- **`mkIf`-false leaves an option UNDEFINED, not false.** Accessing an
  undefined gated option throws (`accessed but has no value defined`), and
  `.or` does NOT catch eval errors. Every gated option must declare a
  default, and consumers read through defaults.
- **`types.lazyAttrsOf` keeps phantom leaves.** An `mkIf`-false definition in
  a lazyAttrsOf option still appears in `attrNames` (a placeholder leaf whose
  access throws). Strict `types.attrsOf` drops it. The substrate uses only
  strict `attrsOf` — keep it that way wherever a surface is enumerated
  (reports, folds, verify lanes).
- **`types.attrsOf` is a function** — `lib.types.attrsOf lib.types.anything`,
  never bare `lib.types.attrsOf` (a lambda-wants-args type error).
- **Never shape a module's `config` attrset with `//` on a `pkgs`-derived
  condition** (`{ … } // lib.optionalAttrs pkgs.stdenv.isDarwin { … }`): the
  module system needs the attr NAMES before `pkgs` exists — infinite
  recursion at the `pkgs` line. Use `lib.mkMerge [ { … } (lib.mkIf cond
  { … }) ]`. A `mkIf false` block may only vary the VALUE of options both
  platforms declare (darwin's activationScripts have no `deps`) — it may
  NOT name an option the other platform never declares: unknown config
  attrs are checked before mkIf conditions apply (see the leg-file rule
  above). Options that exist on one platform only go in that platform's
  leg file.
- **A darwin `writeShellApplication` must not carry `pkgs.coreutils`**: its
  runtimeInputs PREPEND GNU tools that shadow the BSD ones (`stat -f %Su
  /dev/console` becomes filesystem status). Darwin programs keep
  runtimeInputs empty, put `/usr/bin:/bin:/usr/sbin:/sbin` FIRST, and call
  BSD-specific tools by absolute path (`/usr/bin/stat`).

## home-manager traps (exercised)

- **HM's systemd module is inert for root.** Its config is `mkIf (cfg.enable
  && config.home.username != "root")`: `systemd.user.services.<x>` evaluates
  fine and NOTHING ships on a root home (no unit file, no sd-switch). A user
  service that must run on any host is a plain
  `xdg.configFile."systemd/user/<x>.service".text` plus its own activation
  (`entryAfter [ "linkGeneration" ]`): `daemon-reload`, `enable`, restart
  when the unit's `readlink -f` differs from a stamp in the state tree or
  the unit is inactive, `loginctl enable-linger` when Linger=no, and on
  removal stop + delete the `default.target.wants` link + the stamp. Defer
  with the exact command when `systemctl --user show-environment` fails.
- **The activation PATH carries no host tools** (systemctl, loginctl,
  dpkg/apt, sudo, git): append the system dirs inside the activation or the
  program (`PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`)
  — writeShellApplication's runtimeInputs only prepend the closure, and a
  `command -v systemctl` probe silently takes the 'no systemd' branch.
- **Standalone HM re-imports nixpkgs when `nixpkgs.*` is set**: its
  `modules/misc/nixpkgs.nix` builds `_pkgs = import pkgsPath config.nixpkgs`
  and overrides the passed `pkgs`. Passing `pkgs` built with the overlays AND
  setting `nixpkgs.overlays`/`nixpkgs.config` in a module instantiates the
  set twice (the overlay ran 24× in one home eval). Set one or the other.
- **Use upstream `programs.*` for shell init; order with `lib.mkOrder`.**
  `programs.bash.initExtra` / `programs.zsh.initContent` merge by order:
  `mkOrder 2000` puts the operator's extras last; a hook that must follow the
  prompt (direnv after starship) gets its own `mkOrder 1950` line with the
  module's integration off (`programs.direnv.enableBashIntegration = false`).
  Env goes to `home.sessionVariables` (raw lines: `home.sessionVariablesExtra`)
  — it lands in hm-session-vars, sourced by bash `.profile` and zsh `.zshenv`,
  not `.bashrc`; a test asserting session env greps the sourced file
  (`grep -o '/nix/store/[^"]*hm-session-vars.sh' .profile`), not `.profile`.
  `programs.eza` adds its own la/ll/lla/lt aliases.
- **Shell snippets for rc files are nix strings, not `.sh` payload files**: a
  `.sh` file gets shellchecked by the battery and needs directive comments,
  which `builtins.readFile` then pastes into every user's rc file.
- **Verify rc behavior with `bash -ic`**, not `bash -lc`: HM's `.bashrc` returns
  early for non-interactive shells, so aliases and functions read as absent in
  a login-only probe. Read the BUILT files under `<gen>/home-files/` before
  switching.
- **Builder scripts compute names at eval time**: `${baseNameOf p}` instead of
  `$(basename "${p}")` in `runCommand` — the builder PATH carries no
  coreutils in minimal environments (the container e2e fails where the host
  build passed).
- **Removing a gate can widen a default elsewhere**: flipping an enable's
  default to true re-activates every OTHER module gated only on that flag
  (a duplicate package line in another domain). Grep every consumer of the
  option before changing its default.

## Test-hygiene rule (exercised)

A test asserting on repo-local mutable state (e.g. the shim dispatch test
assuming `hosts/machine.json` still holds TEMPLATE) breaks the moment a real
host captures its identity. Tests own their fixtures: build the fixture
(template or captured) inside the test, never read the live checkout's state.

## Docs read for this (primary sources)

- nixpkgs manual, Module System chapter (evalModules, specialArgs, class).
- nixpkgs `lib/options.nix` (mkOption/mkEnableOption definitions).
- nix.dev module-system deep-dive (conditional definitions, mkIf).
- Nix language reference (operator precedence, attrpaths, `with` caveats).
- NixOS manual 'Writing NixOS Modules' — the deeper module-system reference
  (the nixpkgs chapter is explicitly incomplete).
