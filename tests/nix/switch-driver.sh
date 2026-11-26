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

# fresh — a committed checkout, its machine file, a profile at generation 3
fresh() {
	rm -rf "${work:?}/co" "${work:?}/state" "${work:?}/gen" "${work:?}/home" "${work:?}/origin.git" "${work:?}/other" "${work:?}/sys"
	mkdir -p "$work/co/hosts/local" "$work/gen" "$work/bin" "$work/home" "$work/state/nix/profiles"
	printf '%s\n' '{"host":"corrhos","user":"op","home":"/home/op","system":"x86_64-linux","settings":{}}' \
		>"$work/co/hosts/local/machine.json"
	printf '%s\n' '{"nodes":{"nixpkgs":{"locked":{"rev":"aaaaaaa1111"}}}}' >"$work/co/flake.lock"
	printf 'hosts/local/\n' >"$work/co/.gitignore"
	g init -q -b main
	g add -A
	g commit -q -m init
	head=$(g rev-parse HEAD)
	printf '#!/bin/sh\necho activate-ran >>"%s"\n' "$work/log" >"$work/gen/activate"
	chmod +x "$work/gen/activate"
	ln -s "$work/gen" "$work/state/nix/profiles/home-manager-3-link"
	ln -s home-manager-3-link "$work/state/nix/profiles/home-manager"
	mkdir -p "$work/sys"
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

printf 'switch-driver.sh: OK (plane guards, the flake keys, the baked keys, update over origin, failed build, the system runner)\n'
