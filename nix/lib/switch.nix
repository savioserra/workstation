# The write plane, composed: the verb scaffold (apply|rollback|update|sync,
# home and system planes, the detached system runner, the switch.log
# receipt) plus the lifecycle routines the workstation modules register
# (workstation.routines.<event>) — each routine runs at its event, reports,
# and never fails the switch.
{
  lib,
  pkgs,
  homeAttr ? null,
  systemAttr ? null,
  routines ? { },
}:
let
  rebuild = if pkgs.stdenv.hostPlatform.isDarwin then "darwin-rebuild" else "nixos-rebuild";

  events = [
    "after-apply"
    "after-rollback"
    "after-update"
  ];

  routineScript = event: r: pkgs.writeShellScript "ws-routine-${event}-${r.name}" r.text;

  routine = event: r: ''
    echo "workstation-switch: routine ${r.name} (${event})"
    if ! ${routineScript event r}; then
      echo "workstation-switch: routine ${r.name} (${event}) FAILED — the switch stands, the routine did not run clean" >&2
    fi
  '';

  runRoutines = ''
    run_routines() {
      case "$1" in
        ${lib.concatStringsSep "\n" (
          map (event: ''
            ${event})
              ${lib.concatStringsSep "\n" (map (routine event) (routines.${event} or [ ]))}
              ;;
          '') events
        )}
        *) ;;
      esac
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
  '';

  resolveHomeProfile = ''
    state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
    user_nix_profiles="''${state_home}/nix/profiles"
    hm_gcroots="''${state_home}/home-manager/gcroots"
    global_profiles="''${NIX_STATE_DIR:-/nix/var/nix}/profiles/per-user/''${USER:-$(id -un 2>/dev/null || true)}"
    if [ -d "$user_nix_profiles" ]; then
      profile="''${user_nix_profiles}/home-manager"
    elif [ -d "$hm_gcroots" ]; then
      profile="''${hm_gcroots}/current-home"
    elif [ -d "$global_profiles" ]; then
      profile="''${global_profiles}/home-manager"
    else
      echo "workstation-switch: no home-manager profile dir — tried $user_nix_profiles, $hm_gcroots and $global_profiles — nothing receipted" >&2
      exit 1
    fi
    # the gcroot layout carries no numbered link: re-register the live
    # generation into a numbered profile so receipts and rollback keep
    # their shape
    if [ "$profile" = "$hm_gcroots/current-home" ] && [ ! -e "''${user_nix_profiles}/home-manager" ]; then
      mkdir -p "$user_nix_profiles"
      nix-env --profile "''${user_nix_profiles}/home-manager" --set "$(readlink -f "$profile")" >/dev/null 2>&1 || true
      profile="''${user_nix_profiles}/home-manager"
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
  home_activate="''${WORKSTATION_SWITCH_HOME_ACTIVATE:-}"
  ${guards}
  ${runRoutines}

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
    # the runner payload carries its env explicitly: a tmux session on an
    # existing server inherits the server's environment, not the caller's
    inner="WORKSTATION_SWITCH_DETACHED=1 WORKSTATION_SWITCH_FLAKE=\"$flake\" WORKSTATION_SWITCH_MACHINE=\"''${WORKSTATION_SWITCH_MACHINE:-}\" WORKSTATION_SWITCH_HOME_ATTR=\"$home_attr\" WORKSTATION_SWITCH_SYSTEM_ATTR=\"$system_attr\" PATH=\"$PATH\" $0 $cmd --system"
    if command -v tmux >/dev/null 2>&1; then
      if tmux has-session -t ws-switch 2>/dev/null; then
        echo "workstation-switch: the ws-switch session exists — a system switch is in flight; attach: tmux attach -t ws-switch (log: $log)" >&2
        exit 1
      fi
      if tmux new-session -d -s ws-switch "sh -c '$inner 2>&1 | tee -a $log'"; then
        echo "workstation-switch: system switch in tmux session ws-switch (attach: tmux attach -t ws-switch; log: $log)"
        if [ -t 0 ]; then
          exec tmux attach -t ws-switch
        fi
        exit 0
      fi
    fi
    nohup setsid sh -c "$inner >> '$log' 2>&1" >/dev/null 2>&1 &
    echo "workstation-switch: system switch detached (log: $log)"
    exit 0
  fi

  event=""
  case "$plane:$cmd" in
    home:apply|home:sync)
      need_home
      if [ -n "$home_activate" ]; then
        "$home_activate"
      else
        need_flake
        gen="$(nix build --no-link --print-out-paths "$flake#homeConfigurations.\"$home_attr\".activationPackage" "''${override[@]}" | tail -n 1)"
        "$gen/activate"
      fi
      ${resolveHomeProfile}
      event=after-apply
      ;;
    home:rollback)
      ${resolveHomeProfile}
      nix-env --profile "$profile" --rollback
      "$profile/activate"
      event=after-rollback
      ;;
    home:update|system:update)
      checkout="''${WORKSTATION_SWITCH_CHECKOUT:-}"
      if [ -z "$checkout" ]; then
        echo "workstation-switch: update needs the checkout — run it through the launcher (workstation update)" >&2
        exit 2
      fi
      # the rolling verb: pull the substrate, bump the lock, commit it
      # (the build only sees committed HEAD), then switch — no git
      # ceremony for the consumer; every step stops clean on conflict
      if [ -n "$(git -C "$checkout" status --porcelain -- . ':!flake.lock')" ]; then
        echo "workstation-switch: the checkout carries uncommitted changes — update moves only a clean tree (yours stays untouched):" >&2
        git -C "$checkout" status --porcelain -- . ':!flake.lock' | head -5 >&2
        exit 1
      fi
      if git -C "$checkout" remote get-url origin >/dev/null 2>&1; then
        if ! git -C "$checkout" pull --ff-only --quiet 2>/dev/null; then
          branch="$(git -C "$checkout" rev-parse --abbrev-ref HEAD)"
          if git -C "$checkout" diff --quiet "origin/$branch...HEAD" -- . ':!flake.lock' 2>/dev/null \
            && git -C "$checkout" rebase "origin/$branch" >/dev/null 2>&1; then
            echo "workstation-switch: local lock commits rebased on origin"
          else
            echo "workstation-switch: pull failed (diverged from origin) — resolve by hand, then: workstation update" >&2
            git -C "$checkout" rebase --abort >/dev/null 2>&1 || true
            exit 1
          fi
        fi
      fi
      old_rev="$(jq -r '.nodes.nixpkgs.locked.rev' "$checkout/flake.lock" 2>/dev/null || echo unknown)"
      nix flake update --flake "$checkout"
      new_rev="$(jq -r '.nodes.nixpkgs.locked.rev' "$checkout/flake.lock" 2>/dev/null || echo unknown)"
      if ! git -C "$checkout" diff --quiet -- flake.lock; then
        git -C "$checkout" add flake.lock
        git -C "$checkout" -c user.name=workstation -c user.email=workstation@localhost \
          commit --quiet -m "lock: nixpkgs ''${old_rev:0:7}..''${new_rev:0:7}"
        echo "workstation-switch: lock committed (nixpkgs ''${old_rev:0:7}..''${new_rev:0:7})"
      else
        echo "workstation-switch: inputs already current"
      fi
      run_routines after-update
      echo "workstation-switch: switching to the updated tree"
      export WORKSTATION_SWITCH_FLAKE WORKSTATION_SWITCH_MACHINE WORKSTATION_SWITCH_HOME_ATTR WORKSTATION_SWITCH_SYSTEM_ATTR
      exec "$0" apply $([ "$plane" = system ] && echo --system)
      ;;
    system:apply|system:sync)
      need_system
      need_flake
      ${rebuild} switch --flake "$flake#$system_attr" "''${override[@]}"
      profile=/nix/var/nix/profiles/system
      event=after-apply
      ;;
    system:rollback)
      ${rebuild} switch --rollback
      profile=/nix/var/nix/profiles/system
      event=after-rollback
      ;;
  esac

  ${readAndPublish}
  run_routines "$event"
''
