#!/bin/sh
# The lazy-lock merge gate: the merge program over a scratch home.
#
# | Case | Contract |
# | --- | --- |
# | 1 | an absent lockfile takes the baseline, byte for byte |
# | 2 | the baseline pins win over the deployed ones |
# | 3 | a deployed extra with an installed plugin directory stays |
# | 4 | a deployed extra without one is pruned |
# | 5 | the output is lazy.nvim's lockfile shape: names in ASCII order, one line per entry, the canonical field order |
# | 6 | a lockfile that is not a JSON object fails closed |
#
# usage: lazy-lock-merge.sh <merge program> <baseline.json>
set -eu

merge=$1
baseline=$2

work=$(mktemp -d "${TMPDIR:-/tmp}/lazy-lock-merge.XXXXXX")
trap 'rm -rf "$work"' EXIT

fail() {
	printf 'lazy-lock-merge.sh: FAIL: %s\n' "$*" >&2
	exit 1
}

home="$work/home"
mkdir -p \
	"$home/.local/share/nvim/lazy/oasis.nvim" \
	"$home/.local/share/nvim/lazy/host-extra.nvim" \
	"$home/.local/share/nvim/lazy/zzz.nvim"
export HOME="$home"
# the plugin directory lives under the data root: the fixture owns it
export XDG_DATA_HOME="$home/.local/share"

# the merge program: the built payload is executable, the source is not
run_merge() {
	if [ -x "$merge" ]; then
		"$merge" "$@"
	else
		sh "$merge" "$@"
	fi
}

deployed="$work/deployed.json"
cat >"$deployed" <<'JSON'
{
  "LazyVim": { "branch": "stale", "commit": "deadbeef" },
  "oasis.nvim": { "branch": "main", "commit": "aaaa" },
  "host-extra.nvim": { "branch": "main", "commit": "bbbb" },
  "ghost.nvim": { "branch": "main", "commit": "cccc" },
  "zzz.nvim": { "pinned": true, "version": "1.2.3", "commit": "dddd", "branch": "main" }
}
JSON

# 1 — an absent lockfile takes the baseline, byte for byte
run_merge "$baseline" "$work/absent.json" >"$work/absent.out"
cmp -s "$baseline" "$work/absent.out" ||
	fail "an absent lockfile must take the baseline"

# 2, 3, 4 — the merge over the deployed lockfile
out=$(run_merge "$baseline" "$deployed")

printf '%s' "$out" | grep -q '"LazyVim": { "branch": "main", "commit": "c10948c50b18fae7f256433afdef09e432410480" }' ||
	fail "the baseline pins must win over the deployed ones"
printf '%s' "$out" | grep -q '"host-extra.nvim": { "branch": "main", "commit": "bbbb" }' ||
	fail "a deployed extra with an installed plugin directory must stay"
if printf '%s' "$out" | grep -q 'ghost.nvim'; then
	fail "a deployed extra without an installed plugin directory must be pruned"
fi

# 5 — the lockfile shape
printf '%s' "$out" | head -n 2 | tail -n 1 | grep -qE '^  "[A-Za-z0-9._-]+": \{ "[a-z]+": "[^"]*"(, "[a-z]+": ("[^"]*"|true))? \},?$' ||
	fail "the entries must be one per line, the names quoted, the fields canonical"
printf '%s' "$out" | grep -q '^  "zzz.nvim": { "branch": "main", "commit": "dddd", "version": "1.2.3", "pinned": true }' ||
	fail "the canonical field order must lead, the rest sorted"

# 6 — a lockfile that is not a JSON object fails closed
printf '[1, 2, 3]\n' >"$work/array.json"
if run_merge "$baseline" "$work/array.json" >/dev/null 2>&1; then
	fail "a lockfile that is not a JSON object must fail closed"
fi

printf 'lazy-lock-merge.sh: OK (the baseline seeds, the baseline wins, the installed extra stays, the orphan is pruned, the shape holds, a non-object fails closed)\n'
