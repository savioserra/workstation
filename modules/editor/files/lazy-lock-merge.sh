# The lazy-lock merge: the committed baseline pins merged into the live,
# runtime-extended lazy-lock.json. The baseline pins win on conflict; a
# host extra with an installed plugin directory stays; the rest are
# pruned. The output is lazy.nvim's own lockfile shape: the names in
# ASCII order, one line per entry, the canonical field order.
#
# usage: lazy-lock-merge <baseline.json> <deployed.json>
set -eu

baseline=$1
deployed=$2

# an absent or empty lockfile takes the baseline; an identical one keeps
# the baseline's bytes
if [ ! -s "$deployed" ] || cmp -s "$baseline" "$deployed"; then
	cat "$baseline"
	exit 0
fi

data_root=${XDG_DATA_HOME:-$HOME/.local/share}
lazy_root="$data_root/nvim/lazy"

installed=$(
	if [ -d "$lazy_root" ]; then
		for p in "$lazy_root"/*; do
			[ -e "$p" ] || continue
			printf '%s\n' "${p##*/}"
		done | jq -R -s 'split("\n") | map(select(length > 0))'
	else
		printf '[]\n'
	fi
)

jq -n -r \
	--slurpfile baseline "$baseline" \
	--slurpfile deployed "$deployed" \
	--argjson installed "$installed" '
	def canonical: ["branch", "build", "commit", "version", "semver", "pinned"];

	# the fields of one pin: the canonical order first, the rest sorted
	def pin_fields:
		. as $pin
		| canonical as $order
		| (($order | map(. as $f | select($pin | has($f)) | $f))
			+ ($pin | keys | map(select(. as $k | ($order | index($k)) == null)) | sort)) as $fields
		| $fields
		| map(. as $k
			| "\($k | @json): \(if ($pin[$k] | type) == "string" then ($pin[$k] | @json) else ($pin[$k] | tojson) end)")
		| join(", ");

	# the lockfile text: names in ASCII order, one line per entry
	def lock_text:
		(to_entries | sort_by(.key)
			| map(. as $e | "  \($e.key | @json): { \($e.value | pin_fields) }")) as $lines
		| if ($lines | length) == 0 then "{\n}"
			else "{\n" + ($lines | join(",\n")) + "\n}"
			end;

	($baseline[0]) as $b
	| ($deployed[0]) as $d
	| if ($b | type) != "object" then
		error("the baseline is not a JSON object")
	elif ($d | type) != "object" then
		error("the deployed lockfile is not a JSON object")
	else
		($b + (reduce ($d | to_entries[]) as $e ({};
			if ($b | has($e.key)) then
				.
			elif ($installed | index($e.key)) != null then
				. + { ($e.key): $e.value }
			else
				.
			end)))
		| lock_text
	end
'
