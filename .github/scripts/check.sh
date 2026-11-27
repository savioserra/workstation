#!/bin/sh
# The check matrix: the nixpkgs-native substrate is declared state, so the
# matrix is static source gates plus the nix eval read gate. Behavioral
# verification — the docker-nix acceptance (closures) and the container
# E2E (activation + consumers) — is owned by docs/testing.md.
#
# Ordering: the identity gate runs first (cheap source grep), then the
# history-prose gate, then the shell checks, then the nix eval reads (skipped with a loud note
# where nix is absent — the docker acceptance owns them there).
set -eu
repo_root=$(CDPATH='' cd -P "$(dirname "$0")/../.." && pwd -P)
cd "$repo_root"
fail=0

step() { printf '\n== %s\n' "$1"; }

step 'nix identity gate (the repo is a template: identity is captured at install time only — hosts/local/machine.json, gitignoreds)'
# A gate may only pass on a real no-match (git grep exit 1): a tooling
# failure (exit 128 — not a checkout, a bad pathspec) fails CLOSED, never
# reads as "no match".
gate() {
	# gate <name> <hit message> <grep args...>
	name=$1
	hitmsg=$2
	shift 2
	rc=0
	out=$("$@" 2>&1) || rc=$?
	case $rc in
	1) return 0 ;;
	0)
		fail=1
		if [ -n "$out" ]; then printf '%s\n' "$out"; fi
		printf '%s\n' "$hitmsg" >&2
		;;
	*)
		fail=1
		if [ -n "$out" ]; then printf '%s\n' "$out" >&2; fi
		printf '%s: %s exited %s — failing closed (a gate only passes on a real no-match)\n' "$name" "$1" "$rc" >&2
		;;
	esac
}
# the identity gate reads git grep's own status: a hit is 0, a real
# no-match is 1, a tooling failure is any other code and fails closed
identity_hits() {
	rc=0
	out=$(git grep -iE 'savio|shyylol' -- . ':(exclude).github/scripts/check.sh') || rc=$?
	case $rc in
	0)
		hits=$(printf '%s\n' "$out" | grep -vF 'savioserra/workstation' || true)
		if [ -n "$hits" ]; then
			printf '%s\n' "$hits"
			return 0
		fi
		return 1
		;;
	1) return 1 ;;
	*) return "$rc" ;;
	esac
}
gate 'identity gate' \
	'identity gate: hardcoded personal identity in the tracked tree — the legs are templates; hosts/local/machine.json (captured by workstation init, kept uncommitted) is the only identity surface' \
	identity_hits

step 'history-prose gate (the tree describes the current world)'
# dates, card ids, ruling citations and history words belong in git
# history; the pattern
# is assembled at runtime so this gate's own source never matches
history_pattern='20[0-9]{2}-[01][0-9]-[0-3][0-9]|\bt_[0-9a-f]{8}\b|ADDEN''DUM|operator (rul''ing|decis''ion|direct''ive|permiss''ion)|\b([Ll]ega''cy|[Rr]eti''red?|[Rr]eti''rement|[Mm]igra''tion|[Ff]orm''erly|[Nn]o lon''ger|[Cc]ut''over|chez''moi)\b'
gate 'history-prose gate' \
	'history-prose gate: a date, card id, ruling citation or history word in the tracked tree — describe the current world; history lives in git' \
	git grep -nIE "$history_pattern" -- . ':(exclude)*.lock' ':(exclude)*-lock.json'


step 'the gate tools (the lock carries ShellCheck and nixfmt)'
# the battery, the CI job and the docker lane run the same tools: the
# lock's. Without a nix install the PATH tools answer.
locked_tool() {
	nix --extra-experimental-features 'nix-command flakes' build --no-link \
		--print-out-paths --inputs-from "$repo_root" "nixpkgs#$1" 2>/dev/null |
		tail -n 1 |
		sed "s|\$|/bin/$2|"
}
shellcheck_bin=
nixfmt_bin=
if command -v nix >/dev/null 2>&1; then
	shellcheck_bin=$(locked_tool shellcheck.bin shellcheck)
	nixfmt_bin=$(locked_tool nixfmt nixfmt)
	if [ -z "$shellcheck_bin" ] || [ -z "$nixfmt_bin" ]; then
		printf 'the locked gate tools did not build (shellcheck, nixfmt)\n' >&2
		exit 1
	fi
else
	if command -v shellcheck >/dev/null 2>&1; then
		shellcheck_bin=$(command -v shellcheck)
	fi
	if command -v nixfmt >/dev/null 2>&1; then
		nixfmt_bin=$(command -v nixfmt)
	fi
fi
printf 'shellcheck: %s\nnixfmt: %s\n' "${shellcheck_bin:-absent}" "${nixfmt_bin:-absent}"

step 'shell syntax (sh -n) and ShellCheck'
{
	find bin modules .github/scripts tests hosts -type f \( -name '*.sh' -o -name 'workstation' \) -print
	printf 'install.sh\n'
} | while IFS= read -r file; do
	sh -n "$file" || exit 1
	if [ -n "$shellcheck_bin" ]; then
		"$shellcheck_bin" -s sh "$file" || exit 1
	fi
done || fail=1
if [ -z "$shellcheck_bin" ]; then
	printf 'ShellCheck unavailable here; required in the Linux CI job.\n' >&2
fi

step 'nixfmt gate (RFC 166)'
if [ -n "$nixfmt_bin" ]; then
	{ find flake.nix modules nix hosts tests -type f -name '*.nix' -print; } |
		xargs "$nixfmt_bin" --check || fail=1
else
	printf 'nixfmt unavailable here; the nix CI job owns the format gate.\n' >&2
fi

step 'launcher shim dispatch gate (stubbed nix, stubbed switch driver)'
sh .github/scripts/shim-dispatch.sh || fail=1

step 'nix eval read gate (#workstation.report.<verb> answers)'
if command -v nix >/dev/null 2>&1; then
	for verb in status plan capabilities selectable selections; do
		nix --extra-experimental-features 'nix-command flakes' \
			eval --json ".#workstation.report.$verb" >/dev/null || fail=1
	done
	printf 'status counts: '
	nix --extra-experimental-features 'nix-command flakes' \
		eval --json .#workstation.report.status.counts
else
	printf 'nix unavailable here; the docker acceptance owns the eval gate (docs/testing.md).\n' >&2
fi

step 'whitespace (git diff --check)'
# a .patch file is a unified diff: its context lines carry the space-before-tab
# the gate hunts, so the artifact itself stays out of the scan
git diff --check -- . ':!*.patch' || fail=1

[ "$fail" -eq 0 ] || { printf '\ncheck.sh: FAILED\n' >&2; exit 1; }
printf '\ncheck.sh: OK\n'
