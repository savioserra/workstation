#!/bin/sh
# The switch driver gate: the real workstation-switch over a scratch
# checkout, a stubbed nix and a staged home-manager profile.
# usage: switch-driver.sh <driver without a home plane> <driver with a stale home key>
#
# | # | case | holds |
# | 1 | no home plane, apply | refuses, builds nothing |
# | 2 | no home plane, update | refuses, the checkout stays |
# | 3 | stale baked key, apply | builds the machine file's key, activates, receipts the commit |
# | 4 | update | the lock commits, the build names the new HEAD |
# | 5 | the build fails | the switch stops, nothing activates |
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
	rm -rf "${work:?}/co" "${work:?}/state" "${work:?}/gen" "${work:?}/home"
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
	: >"$work/log"
}

# stub <ok|fail> — nix: logs its arguments, rewrites the lock, answers a build
stub() {
	if [ "$1" = ok ]; then build="echo $work/gen"; else build='exit 1'; fi
	cat >"$work/bin/nix" <<EOF
#!/bin/sh
echo "NIX: \$*" >>"$work/log"
case "\$*" in
"flake update"*) printf '%s\n' '{"nodes":{"nixpkgs":{"locked":{"rev":"bbbbbbb2222"}}}}' >"$work/co/flake.lock" ;;
build*) $build ;;
esac
EOF
	chmod +x "$work/bin/nix"
}

# drive <driver> <verb> — rc in \$rc, stderr in \$work/err
drive() {
	rc=0
	env -i PATH="$work/bin:$PATH" HOME="$work/home" USER=op XDG_STATE_HOME="$work/state" \
		WORKSTATION_SWITCH_FLAKE="git+file://$work/co?rev=$head" \
		WORKSTATION_SWITCH_MACHINE="$work/co/hosts/local" \
		WORKSTATION_SWITCH_CHECKOUT="$work/co" \
		"$1" "$2" >"$work/out" 2>"$work/err" || rc=$?
}

logged() {
	grep -q -- "$1" "$work/log"
}

# 1
fresh
stub ok
drive "$nohome" apply
[ "$rc" = 2 ] || fail "1: a leg without a home plane must refuse apply with rc 2 (rc $rc)"
! logged '^NIX: build' || fail '1: a refused apply must build nothing'

# 2
fresh
stub ok
drive "$nohome" update
[ "$rc" = 2 ] || fail "2: a leg without a home plane must refuse update with rc 2 (rc $rc)"
[ "$(g rev-parse HEAD)" = "$head" ] || fail '2: a refused update must leave the checkout at its commit'
[ ! -s "$work/log" ] || fail '2: a refused update must run no nix'

# 3
fresh
stub ok
drive "$stale" apply
[ "$rc" = 0 ] || fail "3: apply over a stale baked key must succeed (rc $rc)"
logged 'homeConfigurations."op@corrhos"' || fail '3: the build must name the machine file key'
logged 'activate-ran' || fail '3: the built generation must activate'
grep -q "generation 3 applied .* at $head" "$work/state/workstation/switch.log" ||
	fail '3: the receipt must name the generation and the commit'

# 4
fresh
stub ok
drive "$stale" update
[ "$rc" = 0 ] || fail "4: update must succeed (rc $rc)"
new=$(g rev-parse HEAD)
[ "$new" != "$head" ] || fail '4: update must commit the lock'
grep '^NIX: build' "$work/log" | grep -q "rev=$new" || fail '4: the build must name the new HEAD'
! grep '^NIX: build' "$work/log" | grep -q "rev=$head" || fail '4: the build must leave the previous HEAD'

# 5
fresh
stub fail
drive "$stale" apply
[ "$rc" != 0 ] || fail '5: a failed build must fail the switch'
! logged 'activate-ran' || fail '5: a failed build must activate nothing'
! grep -q '/activate' "$work/err" || fail '5: a failed build must stop before the activate path'

printf 'switch-driver.sh: OK (plane guards, machine-file key, update re-pin, failed build)\n'
