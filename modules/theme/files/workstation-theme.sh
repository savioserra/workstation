# workstation-theme: the runtime theme pick.
#
# | Verb | Effect |
# | --- | --- |
# | (bare), current | the picked theme |
# | list | every theme of this generation, the pick starred |
# | <name>, set <name> | re-link $STATE/current to $THEMES/<name>, reload the consumers |
# | seed | link the default when no live pick exists, reload the consumers |
# | reload | the consumers re-read their files |
#
# THEMES, STATE, DEFAULT and reload_consumers come from the prelude.
set -eu

current="$STATE/current"

die() {
	printf 'workstation-theme: %s\n' "$1" >&2
	exit "${2:-1}"
}

picked() {
	[ -d "$current" ] || return 1
	target=$(readlink "$current") || return 1
	printf '%s\n' "${target##*/}"
}

pick() {
	[ -d "$THEMES/$1" ] || die "unknown theme '$1' (workstation theme list)" 2
	mkdir -p "$STATE"
	ln -sfn "$THEMES/$1" "$current.new"
	mv -Tf "$current.new" "$current"
}

verb=${1:-current}
case "$verb" in
current)
	picked || die 'no theme picked — run: workstation theme <name>'
	;;
list)
	now=$(picked || true)
	for dir in "$THEMES"/*/; do
		name=${dir%/}
		name=${name##*/}
		if [ "$name" = "$now" ]; then
			printf '* %s\n' "$name"
		else
			printf '  %s\n' "$name"
		fi
	done
	;;
seed)
	if ! picked >/dev/null; then
		pick "$DEFAULT"
		printf 'workstation: theme %s (the default)\n' "$DEFAULT"
	fi
	reload_consumers
	;;
reload)
	reload_consumers
	;;
set | *)
	if [ "$verb" = set ]; then
		[ $# -eq 2 ] || die 'usage: workstation theme set <name>' 2
		name=$2
	else
		[ $# -eq 1 ] || die 'usage: workstation theme [list | current | <name>]' 2
		name=$verb
	fi
	pick "$name"
	reload_consumers
	printf 'workstation: theme %s\n' "$name"
	;;
esac
