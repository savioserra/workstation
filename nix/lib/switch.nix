# The write plane, composed: the verb scaffold (apply|rollback|update|sync,
# home and system planes, the detached system runner, the switch.log
# receipt) plus the routine runner over routine trees (`<event>/<name>`,
# nix/modules/routines-home.nix). The outgoing tree is this generation's
# (`routines`); the incoming one rides the incoming generation's root
# (`workstation-routines`), read before its activation.
# | Step | Routines |
# | --- | --- |
# | build, then teardown | the outgoing teardowns the incoming tree lacks; a failure stops the switch |
# | activation, receipt, then activate | the incoming activate routines; a failure reports |
{
  lib,
  pkgs,
  homeAttr ? null,
  systemAttr ? null,
  routines ? null,
}:
let
  rebuild = if pkgs.stdenv.hostPlatform.isDarwin then "darwin-rebuild" else "nixos-rebuild";
  systemConfigurations =
    if pkgs.stdenv.hostPlatform.isDarwin then "darwinConfigurations" else "nixosConfigurations";

  runRoutines = ''
    outgoing=${if routines == null then "" else routines}
    # run_teardown <incoming tree> — before the incoming activation: the
    # outgoing teardowns the incoming tree lacks; a failure stops the switch;
    # an incoming generation without a tree runs none
    run_teardown() {
      [ -n "$outgoing" ] && [ -d "$outgoing/teardown" ] || return 0
      for r in "$outgoing/teardown"/*; do
        [ -x "$r" ] || continue
        rname=''${r##*/}
        if [ -n "''${WORKSTATION_SKIP_TEARDOWN:-}" ]; then
          echo "workstation-switch: routine $rname (teardown) skipped — WORKSTATION_SKIP_TEARDOWN"
        elif [ -z "$1" ] || [ ! -d "$1/teardown" ]; then
          echo "workstation-switch: routine $rname (teardown) skipped — the incoming generation carries no routine tree"
        elif [ ! -e "$1/teardown/$rname" ]; then
          echo "workstation-switch: routine $rname (teardown)"
          if ! as_invoker "$r"; then
            echo "workstation-switch: routine $rname (teardown) FAILED — the switch stops before the activation; fix it and re-apply, or skip the teardowns: WORKSTATION_SKIP_TEARDOWN=1 workstation <verb>" >&2
            exit 1
          fi
        fi
      done
    }
    # run_activate <incoming tree> — after the activation and the receipt
    run_activate() {
      [ -n "$1" ] && [ -d "$1/activate" ] || return 0
      for r in "$1/activate"/*; do
        [ -x "$r" ] || continue
        rname=''${r##*/}
        echo "workstation-switch: routine $rname (activate)"
        if ! as_invoker "$r"; then
          echo "workstation-switch: routine $rname (activate) FAILED — the switch stands, the routine did not run clean" >&2
        fi
      done
    }
    # previous_generation <profile> — the generation link `--rollback`
    # activates (the generation listed before the current one); bash only,
    # no host tool beyond nix-env
    previous_generation() {
      local gens n rest last=""
      gens=$(nix-env --profile "$1" --list-generations 2>/dev/null) || return 0
      while read -r n rest; do
        case "$rest" in
          *"(current)"*)
            if [ -n "$last" ]; then
              printf '%s\n' "$1-$last-link"
            fi
            return 0
            ;;
        esac
        last=$n
      done <<<"$gens"
    }
    # rollback_target <profile> — the previous generation, or a stop
    rollback_target() {
      target=$(previous_generation "$1")
      if [ -z "$target" ]; then
        echo "workstation-switch: no generation before the current one in $1 — nothing to roll back to" >&2
        exit 1
      fi
    }
  '';

  readAndPublish = ''
    link="$(readlink "$profile" 2>/dev/null || true)"
    if [ -z "$link" ] || [ ! -e "$profile" ]; then
      echo "workstation-switch: no generation link at $profile — nothing receipted" >&2
      exit 1
    fi
    gen="''${link%-link}"
    gen="''${gen##*-}"
    if [ -z "$gen" ] || [ "''${gen//[0-9]/}" != "" ]; then
      message="applied (unnumbered profile at $link)"
    elif [ "$gen" -ge 2 ]; then
      message="generation $gen applied (rollback available at $((gen - 1)))"
    else
      message="generation $gen applied (no prior generation)"
    fi
    if [ -n "$flake" ]; then
      case "$flake" in
        *'?rev='*)
          rev="''${flake##*\?rev=}"
          rev="''${rev%%&*}"
          ;;
        *) rev="$(nix eval --raw "$flake#workstation.rev" "''${override[@]}" 2>/dev/null || true)" ;;
      esac
      if [ -n "$rev" ] && [ "$rev" != unknown ]; then
        message="$message at $rev"
      fi
    fi
    echo "workstation-switch: $message"
    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/workstation"
    mkdir -p "$state_dir"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $message" >> "$state_dir/switch.log"
    own "$state_dir" "$state_dir/switch.log"
  '';

  resolveHomeProfile = ''
    state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
    user_nix_profiles="''${state_home}/nix/profiles"
    hm_gcroots="''${state_home}/home-manager/gcroots"
    global_profiles="''${NIX_STATE_DIR:-/nix/var/nix}/profiles/per-user/''${USER:-$(id -un 2>/dev/null || true)}"
    if [ -d "$user_nix_profiles" ] && [ -e "''${user_nix_profiles}/home-manager" ]; then
      profile="''${user_nix_profiles}/home-manager"
    elif [ -e "''${global_profiles}/home-manager" ]; then
      # determinate-nixd unifies profiles asynchronously: a numbered link
      # lives here or in the XDG dir depending on when it last ran
      profile="''${global_profiles}/home-manager"
    elif [ -d "$hm_gcroots" ]; then
      profile="''${hm_gcroots}/current-home"
    else
      echo "workstation-switch: no home-manager profile dir — tried $user_nix_profiles, $global_profiles and $hm_gcroots — nothing receipted" >&2
      exit 1
    fi
  '';

  guards = ''
    need_home() {
      if [ -z "$home_attr" ]; then
        echo "workstation-switch: no default home attr on this leg — set workstation.switch.homeAttr in the host module (or WORKSTATION_SWITCH_HOME_ATTR); this leg's documented mutating seam may be --system" >&2
        exit 2
      fi
    }
    need_system() {
      if [ -z "$system_attr" ]; then
        echo "workstation-switch: no default system attr on this leg — set workstation.switch.systemAttr in the host module (or WORKSTATION_SWITCH_SYSTEM_ATTR)" >&2
        exit 2
      fi
    }
    need_flake() {
      if [ -z "$flake" ]; then
        echo "workstation-switch: no flake to build — run it through the launcher (workstation apply) or set WORKSTATION_SWITCH_FLAKE" >&2
        exit 2
      fi
    }
  '';
in
pkgs.writeShellScriptBin "workstation-switch" ''
  set -eu
  export PATH="${lib.makeBinPath [ pkgs.jq ]}:$PATH"

  usage() {
    echo "usage: workstation-switch apply|rollback|update|sync [--system]" >&2
    exit 2
  }

  cmd="''${1:-}"
  [ -n "$cmd" ] || usage
  shift
  case "$cmd" in
    apply|rollback|sync|update) ;;
    *) usage ;;
  esac

  plane=home
  if [ "''${1:-}" = "--system" ]; then
    plane=system
    shift
  fi
  [ $# -eq 0 ] || usage

  flake="''${WORKSTATION_SWITCH_FLAKE:-}"
  override=()
  if [ -n "''${WORKSTATION_SWITCH_MACHINE:-}" ]; then
    override=(--override-input machine-files "path:$WORKSTATION_SWITCH_MACHINE")
  fi
  home_attr="''${WORKSTATION_SWITCH_HOME_ATTR:-${if homeAttr == null then "" else homeAttr}}"
  system_attr="''${WORKSTATION_SWITCH_SYSTEM_ATTR:-${if systemAttr == null then "" else systemAttr}}"
  home_gen="''${WORKSTATION_SWITCH_HOME_GEN:-}"
  # the keys come from the flake being built (workstation.keys: the machine
  # file's identity, a null key = the leg carries no such plane); the baked
  # attrs answer where the flake does not; the env wins
  if [ "$cmd" != rollback ] && [ -n "$flake" ]; then
    if keys=$(nix eval --json "$flake#workstation.keys" "''${override[@]}" 2>/dev/null); then
      [ -n "''${WORKSTATION_SWITCH_HOME_ATTR:-}" ] || home_attr=$(printf '%s' "$keys" | jq -r '.home // ""')
      [ -n "''${WORKSTATION_SWITCH_SYSTEM_ATTR:-}" ] || system_attr=$(printf '%s' "$keys" | jq -r '.system // ""')
    fi
  fi
  ${guards}
  ${runRoutines}

  # under sudo the invoking user owns the checkout, the state dir and the
  # routines: as_invoker runs a command as that user, own hands files back
  under_sudo() {
    [ "$(id -u)" = 0 ] && [ -n "''${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]
  }
  as_invoker() {
    if under_sudo; then
      sudo -H -u "$SUDO_USER" env "PATH=$PATH" "$@"
    else
      "$@"
    fi
  }
  own() {
    if under_sudo; then
      chown "$SUDO_USER" "$@" 2>/dev/null || true
    fi
  }
  repo() {
    as_invoker git -C "$checkout" "$@"
  }

  # System switches reload system services; one of them can be the
  # transport this very session rides (tailscaled) — a reload boots out
  # the daemon before the new one bootstraps, and a session death in that
  # window leaves the activation half-run and the daemon down. Run every
  # system switch inside a detached on-target runner so the activation
  # always completes: the reloaded service bootstraps, the receipt lands
  # and the routines run even when the calling session dies mid-switch.
  if [ "$plane" = system ] && [ "$cmd" != update ] && [ -z "''${WORKSTATION_SWITCH_DETACHED:-}" ]; then
    if [ "$cmd" != rollback ]; then
      need_system
      need_flake
    fi
    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/workstation"
    mkdir -p "$state_dir"
    log="$state_dir/switch-driver.log"
    status="$state_dir/switch-driver.rc"
    rm -f "$status"
    touch "$log"
    own "$state_dir" "$log"
    seen=$(wc -c < "$log")
    # the runner carries its env explicitly, every value shell-quoted
    inner=$(printf 'WORKSTATION_SWITCH_DETACHED=1 WORKSTATION_SWITCH_FLAKE=%q WORKSTATION_SWITCH_MACHINE=%q WORKSTATION_SWITCH_HOME_ATTR=%q WORKSTATION_SWITCH_SYSTEM_ATTR=%q WORKSTATION_SKIP_TEARDOWN=%q HOME=%q XDG_STATE_HOME=%q SUDO_USER=%q PATH=%q %q %q --system' \
      "$flake" "''${WORKSTATION_SWITCH_MACHINE:-}" "$home_attr" "$system_attr" "''${WORKSTATION_SKIP_TEARDOWN:-}" "$HOME" "''${XDG_STATE_HOME:-$HOME/.local/state}" "''${SUDO_USER:-}" "$PATH" "$0" "$cmd")
    payload=$(printf '%s 2>&1 | tee -a %q; echo "''${PIPESTATUS[0]}" > %q' "$inner" "$log" "$status")
    # finish — the runner's output since launch, its exit code
    finish() {
      tail -c "+$((seen + 1))" "$log"
      own "$log" "$status"
      rc=$(cat "$status" 2>/dev/null || echo 1)
      exit "$rc"
    }
    echo "workstation-switch: system switch detached — waiting (log: $log)"
    if command -v setsid >/dev/null 2>&1; then
      nohup setsid ${pkgs.runtimeShell} -c "$payload" >/dev/null 2>&1 &
    else
      nohup ${pkgs.runtimeShell} -c "$payload" >/dev/null 2>&1 &
    fi
    wait $! || true
    finish
  fi

  incoming=""
  case "$plane:$cmd" in
    home:apply|home:sync)
      need_home
      if [ -n "$home_gen" ]; then
        gen=$home_gen
      else
        need_flake
        gen="$(nix build --no-link --print-out-paths "$flake#homeConfigurations.\"$home_attr\".activationPackage" "''${override[@]}")"
      fi
      incoming="$gen/workstation-routines"
      run_teardown "$incoming"
      "$gen/activate"
      ${resolveHomeProfile}
      ;;
    home:rollback)
      ${resolveHomeProfile}
      rollback_target "$profile"
      incoming="''${target:+$target/workstation-routines}"
      run_teardown "$incoming"
      nix-env --profile "$profile" --rollback
      "$profile/activate"
      ;;
    home:update|system:update)
      checkout="''${WORKSTATION_SWITCH_CHECKOUT:-}"
      if [ -z "$checkout" ]; then
        echo "workstation-switch: update needs the checkout — run it through the launcher (workstation update)" >&2
        exit 2
      fi
      # the plane answers before the checkout moves
      if [ "$plane" = system ]; then need_system; else need_home; fi
      # update: the checkout follows origin, then the switch; the lock
      # moves with origin's commits
      if [ -n "$(repo status --porcelain)" ]; then
        echo "workstation-switch: the checkout carries uncommitted changes — update moves only a clean tree (yours stays untouched):" >&2
        repo status --porcelain | head -5 >&2
        exit 1
      fi
      if repo remote get-url origin >/dev/null 2>&1; then
        before="$(repo rev-parse HEAD)"
        if ! repo pull --ff-only --quiet; then
          branch="$(repo rev-parse --abbrev-ref HEAD)"
          ahead="$(repo rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)"
          if [ "$ahead" != 0 ]; then
            echo "workstation-switch: the checkout carries $ahead commit(s) origin does not — keep them: git pull --rebase; drop them: git reset --hard origin/$branch; then: workstation update" >&2
          else
            echo "workstation-switch: the pull from origin failed — the checkout stays at its commit" >&2
          fi
          exit 1
        fi
        after="$(repo rev-parse HEAD)"
        if [ "$before" = "$after" ]; then
          echo "workstation-switch: the checkout is current with origin"
        else
          echo "workstation-switch: the checkout moved ''${before:0:7}..''${after:0:7}"
        fi
      else
        echo "workstation-switch: the checkout has no origin — switching to its commit"
      fi
      # the pinned ref follows the checkout's new HEAD
      case "$flake" in
        "git+file://$checkout?rev="*)
          flake="git+file://$checkout?rev=$(repo rev-parse HEAD)"
          WORKSTATION_SWITCH_FLAKE=$flake
          ;;
      esac
      echo "workstation-switch: switching to the updated tree"
      export WORKSTATION_SWITCH_FLAKE WORKSTATION_SWITCH_MACHINE WORKSTATION_SWITCH_HOME_ATTR WORKSTATION_SWITCH_SYSTEM_ATTR
      exec "$0" apply $([ "$plane" = system ] && echo --system)
      ;;
    system:apply|system:sync)
      need_system
      need_flake
      toplevel="$(nix build --no-link --print-out-paths "$flake#${systemConfigurations}.\"$system_attr\".config.system.build.toplevel" "''${override[@]}")"
      incoming="$toplevel/workstation-routines"
      run_teardown "$incoming"
      ${rebuild} switch --flake "$flake#$system_attr" "''${override[@]}"
      profile="''${WORKSTATION_SWITCH_SYSTEM_PROFILE:-/nix/var/nix/profiles/system}"
      ;;
    system:rollback)
      profile="''${WORKSTATION_SWITCH_SYSTEM_PROFILE:-/nix/var/nix/profiles/system}"
      rollback_target "$profile"
      incoming="''${target:+$target/workstation-routines}"
      run_teardown "$incoming"
      ${rebuild} switch --rollback
      ;;
  esac

  ${readAndPublish}
  run_activate "$incoming"
''
