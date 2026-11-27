#!/bin/sh
# The switch driver gate: the real workstation-switch over a scratch
# checkout, a stubbed nix and a staged home-manager profile.
# usage: switch-driver.sh <driver without a home plane> <driver with a stale home key>
#
# | # | case | holds |
# | 1 | the flake answers no home key, apply | refuses, builds nothing |
# | 2 | the flake answers no home key, update | refuses, the checkout stays |
# | 3 | stale baked key, apply | builds the flake's key, activates, receipts the commit |
# | 4 | update, origin ahead | the checkout fast-forwards, the build names the new HEAD, the lock stays origin's |
# | 5 | the build fails | the switch stops, nothing activates |
# | 6 | the flake answers no keys | the baked key builds |
# | 7 | no baked home key, the flake answers none | refuses |
# | 8 | update, a local commit origin lacks | refuses, the checkout stays, builds nothing |
# | 9 | update, no origin | switches at the checkout's commit |
# | 11 | system apply, the rebuild fails | the failure reaches the caller |
# | 12 | system apply | the detached runner waits, relays the receipt, exits with the switch's code |
# | 13 | a flake ref with quotes and spaces | reaches the rebuild verbatim |
# | 14 | apply | the outgoing teardowns the incoming tree lacks run before the activation; the incoming activate routines after the receipt; a failed activate routine reports, the switch stands |
# | 15 | apply, a teardown fails | the switch stops before the activation, names the override; WORKSTATION_SKIP_TEARDOWN=1 switches |
# | 16 | apply, the incoming generation carries no routine tree | no teardown runs, the switch proceeds |
# | 17 | rollback | the previous generation's tree decides the teardowns, before its activation; its activate routines run |
# | 18 | system apply | the built toplevel's tree decides the teardowns, before the rebuild |
# | 19 | system rollback | the previous system generation's tree decides the teardowns, before the rebuild |
# | 20 | rollback, a PATH without awk | the previous generation resolves, its activate routines run |
# | 21 | rollback, no previous generation | stops before any teardown or activation |
set -eu

nohome=$1
stale=$2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
	printf 'switch-driver: FAIL — %s\n' "$1" >&2
	[ ! -s "$work/err" ] || sed 's/^/  stderr: /' "$work/err" >&2
	exit 1
}

g() {
	git -C "$work/co" -c user.name=gate -c user.email=gate@localhost "$@"
}

# fresh — a committed checkout, its machine file, a home profile at
# generation 3 over generation 2 and a system profile at 7 over 6; every
# generation carries the incoming routine tree (teardown: kept, broken;
# activate: probe, broken)
fresh() {
	rm -rf "${work:?}/co" "${work:?}/state" "${work:?}/gen" "${work:?}/gen2" "${work:?}/home" "${work:?}/origin.git" "${work:?}/other" "${work:?}/sys" "${work:?}/incoming"
	mkdir -p "$work/co/hosts/local" "$work/gen" "$work/gen2" "$work/bin" "$work/home" "$work/state/nix/profiles" \
		"$work/incoming/teardown" "$work/incoming/activate"
	for r in teardown/kept teardown/broken activate/probe; do
		printf '#!/bin/sh\necho "ROUTINE: %s-incoming" >>"%s"\n' "${r%%/*}" "$work/log" >"$work/incoming/$r"
		chmod +x "$work/incoming/$r"
	done
	printf '#!/bin/sh\nexit 1\n' >"$work/incoming/activate/broken"
	chmod +x "$work/incoming/activate/broken"
	ln -s "$work/incoming" "$work/gen/workstation-routines"
	ln -s "$work/incoming" "$work/gen2/workstation-routines"
	cat >"$work/bin/nix-env" <<'EOF'
#!/bin/sh
echo "NIX-ENV: $*" >>"${0%/bin/*}/log"
[ "$1" = --profile ] || exit 0
p=$2
cur=$(readlink "$p")
for l in "$p"-*-link; do
	n=${l#"$p"-}
	n=${n%-link}
	case "$3" in
	--list-generations)
		if [ "${l##*/}" = "$cur" ]; then echo "   $n   (current)"; else echo "   $n"; fi
		;;
	--rollback)
		[ "${l##*/}" = "$cur" ] || ln -sfn "${l##*/}" "$p"
		;;
	esac
done
EOF
	chmod +x "$work/bin/nix-env"
	printf '%s\n' '{"host":"corrhos","user":"op","home":"/home/op","system":"x86_64-linux","settings":{}}' \
		>"$work/co/hosts/local/machine.json"
	printf '%s\n' '{"nodes":{"nixpkgs":{"locked":{"rev":"aaaaaaa1111"}}}}' >"$work/co/flake.lock"
	printf 'hosts/local/\n' >"$work/co/.gitignore"
	g init -q -b main
	g add -A
	g commit -q -m init
	head=$(g rev-parse HEAD)
	printf '#!/bin/sh\necho activate-ran >>"%s"\n' "$work/log" >"$work/gen/activate"
	printf '#!/bin/sh\necho activate2-ran >>"%s"\n' "$work/log" >"$work/gen2/activate"
	chmod +x "$work/gen/activate" "$work/gen2/activate"
	ln -s "$work/gen2" "$work/state/nix/profiles/home-manager-2-link"
	ln -s "$work/gen" "$work/state/nix/profiles/home-manager-3-link"
	ln -s home-manager-3-link "$work/state/nix/profiles/home-manager"
	mkdir -p "$work/sys"
	ln -s "$work/gen2" "$work/sys/system-6-link"
	ln -s "$work/gen" "$work/sys/system-7-link"
	ln -s system-7-link "$work/sys/system"
	flake_ref="git+file://$work/co?rev=$head"
	printf '#!/bin/sh\necho "REBUILD: $*" >>"%s"\n' "$work/log" >"$work/bin/nixos-rebuild"
	chmod +x "$work/bin/nixos-rebuild"
	: >"$work/log"
}

# with_origin — a bare origin at the checkout's commit, then one commit ahead
with_origin() {
	git clone -q --bare "$work/co" "$work/origin.git"
	g remote add origin "$work/origin.git"
	g fetch -q origin
	g branch -q --set-upstream-to=origin/main
	git clone -q "$work/origin.git" "$work/other"
	printf '%s\n' '{"nodes":{"nixpkgs":{"locked":{"rev":"ccccccc3333"}}}}' >"$work/other/flake.lock"
	git -C "$work/other" -c user.name=gate -c user.email=gate@localhost commit -q -am 'lock: origin'
	git -C "$work/other" push -q origin main
	ahead=$(git -C "$work/other" rev-parse HEAD)
}

# stub <ok|fail> [keys json] — nix: logs its arguments, rewrites the lock,
# answers a build and workstation.keys (no json: the eval fails)
stub() {
	if [ "$1" = ok ]; then build="echo $work/gen"; else build='exit 1'; fi
	rm -f "$work/keys"
	[ -z "${2:-}" ] || printf '%s\n' "$2" >"$work/keys"
	cat >"$work/bin/nix" <<EOF
#!/bin/sh
echo "NIX: \$*" >>"$work/log"
case "\$*" in
*"#workstation.keys"*) cat "$work/keys" 2>/dev/null || exit 1 ;;
"flake update"*) printf '%s\n' '{"nodes":{"nixpkgs":{"locked":{"rev":"bbbbbbb2222"}}}}' >"$work/co/flake.lock" ;;
build*) $build ;;
esac
EOF
	chmod +x "$work/bin/nix"
}

# drive <driver> <verb> [--system] — rc in \$rc, stdout in \$work/out, stderr in \$work/err
drive() {
	rc=0
	env -i PATH="$work/bin:$PATH" HOME="$work/home" USER=op XDG_STATE_HOME="$work/state" \
		WORKSTATION_SWITCH_SYSTEM_PROFILE="$work/sys/system" \
		WORKSTATION_SWITCH_FLAKE="$flake_ref" \
		WORKSTATION_SWITCH_MACHINE="$work/co/hosts/local" \
		WORKSTATION_SWITCH_CHECKOUT="$work/co" \
		"$@" >"$work/out" 2>"$work/err" </dev/null || rc=$?
}

logged() {
	grep -q -- "$1" "$work/log"
}

linux_keys='{"home":"op@corrhos","system":"corrhos"}'
darwin_keys='{"home":null,"system":"op@corrhos"}'

# 1
fresh
stub ok "$darwin_keys"
drive "$stale" apply
[ "$rc" = 2 ] || fail "1: a leg without a home plane must refuse apply with rc 2 (rc $rc)"
! logged '^NIX: build' || fail '1: a refused apply must build nothing'

# 2
fresh
stub ok "$darwin_keys"
drive "$stale" update
[ "$rc" = 2 ] || fail "2: a leg without a home plane must refuse update with rc 2 (rc $rc)"
[ "$(g rev-parse HEAD)" = "$head" ] || fail '2: a refused update must leave the checkout at its commit'
! logged '^NIX: \(build\|flake update\)' || fail '2: a refused update must neither bump the lock nor build'

# 3
fresh
stub ok "$linux_keys"
drive "$stale" apply
[ "$rc" = 0 ] || fail "3: apply over a stale baked key must succeed (rc $rc)"
logged 'homeConfigurations."op@corrhos"' || fail '3: the build must name the key the flake answers'
logged 'activate-ran' || fail '3: the built generation must activate'
grep -q "generation 3 applied .* at $head" "$work/state/workstation/switch.log" ||
	fail '3: the receipt must name the generation and the commit'

# 4
fresh
with_origin
stub ok "$linux_keys"
drive "$stale" update
[ "$rc" = 0 ] || fail "4: update must succeed (rc $rc)"
[ "$(g rev-parse HEAD)" = "$ahead" ] || fail '4: update must fast-forward the checkout to origin'
grep '^NIX: build' "$work/log" | grep -q "rev=$ahead" || fail '4: the build must name the new HEAD'
! grep '^NIX: build' "$work/log" | grep -q "rev=$head" || fail '4: the build must leave the previous HEAD'
! logged '^NIX: flake update' || fail '4: update must leave the lock to origin'
[ -z "$(g status --porcelain)" ] || fail '4: update must leave a clean checkout'

# 5
fresh
stub fail "$linux_keys"
drive "$stale" apply
[ "$rc" != 0 ] || fail '5: a failed build must fail the switch'
! logged 'activate-ran' || fail '5: a failed build must activate nothing'
! grep -q '/activate' "$work/err" || fail '5: a failed build must stop before the activate path'
! logged '^ROUTINE: teardown' || fail '5: a failed build must run no teardown'

# 6
fresh
stub ok
drive "$stale" apply
[ "$rc" = 0 ] || fail "6: apply must succeed on the baked key (rc $rc)"
logged 'homeConfigurations."old@key"' || fail '6: the baked key must build where the flake answers none'

# 7
fresh
stub ok
drive "$nohome" apply
[ "$rc" = 2 ] || fail "7: no home key anywhere must refuse apply with rc 2 (rc $rc)"

# 8
fresh
with_origin
printf 'local\n' >"$work/co/note"
g add note
g commit -q -m local
head=$(g rev-parse HEAD)
stub ok "$linux_keys"
drive "$stale" update
[ "$rc" = 1 ] || fail "8: update over a local commit must refuse with rc 1 (rc $rc)"
[ "$(g rev-parse HEAD)" = "$head" ] || fail '8: a refused update must leave the checkout at its commit'
! logged '^NIX: build' || fail '8: a refused update must build nothing'
grep -q 'git pull --rebase' "$work/err" || fail '8: the refusal must name the way out'

# 9
fresh
stub ok "$linux_keys"
drive "$stale" update
[ "$rc" = 0 ] || fail "9: update without an origin must succeed (rc $rc)"
grep '^NIX: build' "$work/log" | grep -q "rev=$head" || fail '9: the build must name the checkout commit'

# 11
fresh
stub ok "$linux_keys"
printf '#!/bin/sh\nexit 1\n' >"$work/bin/nixos-rebuild"
drive "$stale" apply --system
[ "$rc" != 0 ] || fail '11: a failed rebuild must fail the caller'
[ ! -e "$work/state/workstation/switch.log" ] || fail '11: a failed rebuild must receipt nothing'

# 12
fresh
stub ok "$linux_keys"
drive "$stale" apply --system
[ "$rc" = 0 ] || fail "12: a system apply through the detached runner must succeed (rc $rc)"
grep -q 'generation 7 applied' "$work/state/workstation/switch.log" || fail '12: the runner must receipt'

# 13
fresh
stub ok "$linux_keys"
flake_ref="git+file://$work/co?rev=$head&note=it's \"quoted\" \$HOME; true"
drive "$stale" apply --system
[ "$rc" = 0 ] || fail "13: a flake ref with shell characters must switch (rc $rc)"
grep -Fq "REBUILD: switch --flake $flake_ref#corrhos" "$work/log" || fail '13: the flake ref must reach the rebuild verbatim'

# line <pattern> — the first log line number matching, 0 when absent
line() {
	n=$(grep -n -- "$1" "$work/log" | head -n 1 | cut -d: -f1)
	echo "${n:-0}"
}

# 14
fresh
stub ok "$linux_keys"
drive "$stale" apply
[ "$rc" = 0 ] || fail "14: apply with routines must succeed (rc $rc)"
logged '^ROUTINE: teardown-gone$' || fail '14: an outgoing teardown the incoming tree lacks must run'
! logged '^ROUTINE: teardown-kept$' || fail '14: an outgoing teardown the incoming tree keeps must not run'
[ "$(line '^ROUTINE: teardown-gone$')" -lt "$(line '^activate-ran$')" ] ||
	fail '14: the teardowns must run before the activation'
logged '^ROUTINE: activate-incoming$' || fail '14: the incoming activate routines must run'
! logged '^ROUTINE: activate-outgoing$' || fail '14: the outgoing activate routines must not run'
[ "$(line '^activate-ran$')" -lt "$(line '^ROUTINE: activate-incoming$')" ] ||
	fail '14: the activate routines must run after the activation'
grep -q 'routine broken (activate) FAILED' "$work/err" || fail '14: a failed activate routine must report'
grep -q 'generation 3 applied' "$work/state/workstation/switch.log" || fail '14: the receipt must land'

# 15
fresh
stub ok "$linux_keys"
rm "$work/incoming/teardown/broken"
drive "$stale" apply
[ "$rc" = 1 ] || fail "15: a failed teardown must stop the switch with rc 1 (rc $rc)"
! logged '^activate-ran$' || fail '15: a failed teardown must stop before the activation'
[ ! -e "$work/state/workstation/switch.log" ] || fail '15: a failed teardown must receipt nothing'
grep -q 'routine broken (teardown) FAILED.*WORKSTATION_SKIP_TEARDOWN=1' "$work/err" ||
	fail '15: the stop must name the teardown and the override'
: >"$work/log"
drive env WORKSTATION_SKIP_TEARDOWN=1 "$stale" apply
[ "$rc" = 0 ] || fail "15: WORKSTATION_SKIP_TEARDOWN=1 must switch (rc $rc)"
! logged '^ROUTINE: teardown' || fail '15: WORKSTATION_SKIP_TEARDOWN=1 must run no teardown'
logged '^activate-ran$' || fail '15: WORKSTATION_SKIP_TEARDOWN=1 must activate'

# 16
fresh
stub ok "$linux_keys"
rm "$work/gen/workstation-routines"
drive "$stale" apply
[ "$rc" = 0 ] || fail "16: apply into a generation without a routine tree must succeed (rc $rc)"
! logged '^ROUTINE: teardown' || fail '16: no teardown may run when the incoming generation carries no routine tree'
grep -q 'routine gone (teardown) skipped' "$work/out" || fail '16: the skipped teardowns must report'
logged '^activate-ran$' || fail '16: the switch must proceed'

# 17
fresh
stub ok "$linux_keys"
drive "$stale" rollback
[ "$rc" = 0 ] || fail "17: rollback must succeed (rc $rc)"
logged '^NIX-ENV: --profile .* --rollback' || fail '17: rollback must roll the home profile back'
logged '^ROUTINE: teardown-gone$' || fail '17: an outgoing teardown the previous generation lacks must run'
[ "$(line '^ROUTINE: teardown-gone$')" -lt "$(line '^NIX-ENV: --profile .* --rollback')" ] ||
	fail '17: the teardowns must run before the profile moves'
logged '^activate2-ran$' || fail '17: the previous generation must activate'
logged '^ROUTINE: activate-incoming$' || fail '17: the previous generation activate routines must run'
grep -q 'generation 2 applied' "$work/state/workstation/switch.log" || fail '17: the receipt must name the previous generation'

# 18
fresh
stub ok "$linux_keys"
drive "$stale" apply --system
[ "$rc" = 0 ] || fail "18: a system apply with routines must succeed (rc $rc)"
logged 'nixosConfigurations."corrhos".config.system.build.toplevel' || fail '18: the toplevel must build before the rebuild'
logged '^ROUTINE: teardown-gone$' || fail '18: an outgoing teardown the toplevel tree lacks must run'
[ "$(line '^ROUTINE: teardown-gone$')" -lt "$(line '^REBUILD: switch')" ] ||
	fail '18: the teardowns must run before the rebuild'
logged '^ROUTINE: activate-incoming$' || fail '18: the incoming activate routines must run'

# 19
fresh
stub ok "$linux_keys"
drive "$stale" rollback --system
[ "$rc" = 0 ] || fail "19: a system rollback with routines must succeed (rc $rc)"
logged '^ROUTINE: teardown-gone$' || fail '19: an outgoing teardown the previous system generation lacks must run'
[ "$(line '^ROUTINE: teardown-gone$')" -lt "$(line '^REBUILD: switch --rollback')" ] ||
	fail '19: the teardowns must run before the rebuild'

# 20
fresh
stub ok "$linux_keys"
noawk=$(printf '%s' "$PATH" | tr ':' '\n' | while read -r d; do [ -x "$d/awk" ] || printf '%s:' "$d"; done)
PATH="${noawk%:}" drive "$stale" rollback
[ "$rc" = 0 ] || fail "20: rollback without awk on PATH must succeed (rc $rc)"
logged '^ROUTINE: teardown-gone$' || fail '20: the previous generation must resolve without awk'
logged '^ROUTINE: activate-incoming$' || fail '20: the previous generation activate routines must run without awk'

# 21
fresh
stub ok "$linux_keys"
rm "$work/state/nix/profiles/home-manager-2-link"
drive "$stale" rollback
[ "$rc" = 1 ] || fail "21: rollback without a previous generation must stop with rc 1 (rc $rc)"
! logged '^ROUTINE: ' || fail '21: a stopped rollback must run no routine'
! logged '^NIX-ENV: --profile .* --rollback' || fail '21: a stopped rollback must leave the profile'
grep -q 'nothing to roll back to' "$work/err" || fail '21: the stop must say so'

printf 'switch-driver.sh: OK (plane guards, the flake keys, the baked keys, update over origin, failed build, the system runner, the routines)\n'
