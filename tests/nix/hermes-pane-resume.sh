#!/usr/bin/env bash
# The pane resume helper (modules/agent/files/hermes-pane-resume.sh) over a
# stubbed zellij, a scratch HOME and a stand-in hermes process.
#
# | # | case | expect |
# | 1 | outside zellij | exits at once, no zellij call |
# | 2 | a breadcrumb older than the launch | ignored |
# | 3 | a fresh breadcrumb | set-resurrect-command on the pane with `hermes --resume <id>` |
# | 4 | the ui flag | carried into the command |
# | 5 | the breadcrumb moves to another session | the command follows |
# | 6 | the hermes process ends | the helper exits |
# | 7 | no tty | the zellij pane id keys the breadcrumb |
set -u
helper=$1
python=$2

work=$(mktemp -d)
trap 'kill "$host" 2>/dev/null; rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home/.hermes/terminal-sessions"
cat >"$work/bin/zellij" <<EOF
#!/bin/sh
echo "ZELLIJ: \$*" >>"$work/log"
EOF
chmod +x "$work/bin/zellij"
crumbs=$work/home/.hermes/terminal-sessions

fail() {
	echo "hermes-pane-resume.sh: FAIL $1" >&2
	cat "$work/log" 2>/dev/null >&2
	exit 1
}
crumb() { printf '{"session_id": "%s", "cwd": "/x", "ts": %s}' "$2" "$3" >"$crumbs/$1"; }
run() { # run <pane-id|""> <tty> [ui]
	env -i PATH="$work/bin:/usr/bin:/bin:$PATH" HOME="$work/home" HERMES_PANE_RESUME_INTERVAL=0.2 \
		${1:+ZELLIJ_PANE_ID=$1} "$helper" "$host" "$python" "$since" "$2" ${3:+"$3"} &
	helper_pid=$!
}
wait_log() { # wait_log <pattern>
	for _ in $(seq 1 50); do
		grep -qF -- "$1" "$work/log" 2>/dev/null && return 0
		sleep 0.1
	done
	return 1
}

sleep 300 &
host=$!
since=$(date +%s)

# 1
: >"$work/log"
run "" /dev/pts/9
wait "$helper_pid"
[ ! -s "$work/log" ] || fail '1: a zellij call outside zellij'

# 2
crumb tty-dev-pts-9 old $((since - 100))
run 7 /dev/pts/9
sleep 1
[ ! -s "$work/log" ] || fail '2: a stale breadcrumb was used'

# 3
crumb tty-dev-pts-9 s1 $((since + 1))
wait_log "--resume s1" || fail '3: no resurrect command for the fresh breadcrumb'
grep -qxF "ZELLIJ: action set-resurrect-command --pane-id 7 -- $work/home/.local/bin/hermes --resume s1" "$work/log" ||
	fail '3: wrong resurrect command'
[ "$(grep -c 'resume s1' "$work/log")" = 1 ] || fail '3: an unchanged breadcrumb was re-issued'

# 5
crumb tty-dev-pts-9 s2 $((since + 2))
wait_log "--resume s2" || fail '5: the command did not follow the breadcrumb'
kill "$helper_pid" 2>/dev/null

# 4
: >"$work/log"
crumb tty-dev-pts-4 s3 $((since + 1))
run 3 /dev/pts/4 --tui
wait_log "--resume s3" || fail '4: no resurrect command with a ui flag'
grep -qxF "ZELLIJ: action set-resurrect-command --pane-id 3 -- $work/home/.local/bin/hermes --tui --resume s3" "$work/log" ||
	fail '4: the ui flag was not carried'

# 6
kill "$host"
for _ in $(seq 1 30); do
	kill -0 "$helper_pid" 2>/dev/null || break
	sleep 0.1
done
kill -0 "$helper_pid" 2>/dev/null && fail '6: the helper outlived hermes'

# 7
sleep 300 &
host=$!
: >"$work/log"
crumb zellij_pane_id-5 s4 $((since + 1))
run 5 ""
wait_log "--resume s4" || fail '7: the pane id did not key the breadcrumb'
kill "$host"

printf 'hermes-pane-resume.sh: OK (outside zellij, stale and fresh breadcrumbs, the ui flag, a session switch, exit with hermes, the pane id key)\n'
