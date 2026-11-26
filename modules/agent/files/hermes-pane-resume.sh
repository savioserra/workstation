#!/bin/sh
# Managed by the workstation substrate — the agent capability's pane resume
# helper, started by the hermes launcher inside a zellij pane.
#
# hermes-pane-resume <hermes-pid> <python> <launch-epoch> <tty> [--tui|--cli]
# - keeps this pane's zellij resurrect command on
#   `$HOME/.local/bin/hermes [ui flag] --resume <id>`, <id> = the session the
#   pane shows (the hermes client's terminal breadcrumb)
# - breadcrumb key: `tty-<sanitized tty>`, else `zellij_pane_id-<id>`
# - only breadcrumbs written since <launch-epoch> count
# - exits with the hermes process; a no-op outside zellij
set -u

pid=$1
python=$2
since=$3
tty_name=$4
ui=${5:-}
interval=${HERMES_PANE_RESUME_INTERVAL:-2}

[ -n "${ZELLIJ_PANE_ID:-}" ] || exit 0
command -v zellij >/dev/null 2>&1 || exit 0

sanitize() {
  printf '%s' "$1" | sed 's#^[[:space:]/]*##; s#[[:space:]/]*$##; s#[^A-Za-z0-9._-]#-#g' | cut -c1-120
}
case $tty_name in
/*) key="tty-$(sanitize "$tty_name")" ;;
*) key="zellij_pane_id-$(sanitize "$ZELLIJ_PANE_ID")" ;;
esac
crumb="${HERMES_HOME:-$HOME/.hermes}/terminal-sessions/$key"

last=
while kill -0 "$pid" 2>/dev/null; do
  sid=$("$python" -I -c 'import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8-sig"))
    if float(d.get("ts") or 0) >= float(sys.argv[2]):
        print(str(d.get("session_id") or "").strip())
except Exception:
    pass' "$crumb" "$since" 2>/dev/null)
  if [ -n "$sid" ] && [ "$sid" != "$last" ]; then
    # shellcheck disable=SC2086 # the ui flag is one word or empty
    if zellij action set-resurrect-command --pane-id "$ZELLIJ_PANE_ID" -- \
      "$HOME/.local/bin/hermes" $ui --resume "$sid" >/dev/null 2>&1; then
      last=$sid
    fi
  fi
  sleep "$interval"
done
