#!/bin/sh
# tmux verify — the multiplexer contract (read-only smoke).
#
# Asserts the tmux multiplexer and its theme status bar: the binary runs,
# the managed config and its XDG symlink are deployed, the tmux2k plugin
# checkout is in place, and an isolated server parses the config and carries
# the tmux2k options.
#
# No substrate lane invokes this script; it is the host lane's assertion
# surface (docs/capabilities.md "Package payload rule"). Exits nonzero with
# a message on the first failed assertion.
set -eu

home=${WORKSTATION_VERIFY_HOME:-$HOME}

fail() {
  echo "tmux verify: $1" >&2
  exit 1
}

command -v tmux >/dev/null 2>&1 || fail "tmux not on PATH (the terminal capability did not apply)"
version=$(tmux -V 2>/dev/null) || fail "tmux -V failed"
[ -n "$version" ] || fail "tmux -V printed nothing"

conf=$home/.tmux.conf
[ -f "$conf" ] || fail "the tmux config is missing at $conf (run: workstation apply)"
[ -L "$home/.config/tmux/tmux.conf" ] ||
  fail "the XDG config symlink is missing at $home/.config/tmux/tmux.conf"

plugin=$home/.tmux/plugins/tmux2k
[ -d "$plugin" ] || fail "the tmux2k plugin is missing at $plugin (run: workstation apply)"
[ -f "$plugin/2k.tmux" ] || fail "the tmux2k plugin carries no 2k.tmux"

# the consumer smoke: an isolated server parses the managed config
socket=ws-tmux-verify-$$
tmux -L "$socket" -f "$conf" new-session -d 'sleep 30' >/dev/null 2>&1 ||
  fail "tmux refused the managed config (an isolated server must start with it)"
theme=$(tmux -L "$socket" show-options -gv @tmux2k-theme 2>/dev/null || true)
tmux -L "$socket" kill-server >/dev/null 2>&1 || true
[ -n "$theme" ] || fail "the tmux2k options did not parse (the config carries no @tmux2k-theme)"

echo "tmux verify: ok — $version; the managed config parses and tmux2k carries its options ($theme)"
