#!/bin/sh
# Converge the hermes session toolsets and disabled MCP servers in config.yaml.
# usage: hermes-toolsets <config.yaml> <cli-toolsets,comma> <disabled-mcp,comma>
set -eu
exec "${PYTHON:-python3}" - "$1" "$2" "${3:-}" <<'PYEOF'
import os
import re
import sys

cfg, want_raw, off_raw = sys.argv[1], sys.argv[2], sys.argv[3]
want = [t for t in want_raw.split(",") if t]
off = [t for t in off_raw.split(",") if t]

if not os.path.exists(cfg):
    print("workstation: hermes toolsets ensure deferred — no config.yaml yet")
    sys.exit(0)

text = open(cfg, encoding="utf-8").read()
changed = []

m = re.search(r"(known_builtin_toolsets:\n  cli:\n)((?:    - [a-z_]+\n)+)", text)
if m:
    current = [l.split("    - ")[1] for l in m.group(2).splitlines()]
    if current != want:
        block = "known_builtin_toolsets:\n  cli:\n" + "".join(
            f"    - {t}\n" for t in want
        )
        text = text[: m.start()] + block + text[m.end() :]
        changed.append(f"cli toolsets {len(current)} -> {len(want)}")

for name in off:
    key = f"mcp_servers:\n  {name}:"
    if key not in text:
        continue
    rest = text[text.index(key) :]
    nxt = re.search(r"\n(?=\S)", rest[len(key):])
    end = len(key) + nxt.start() if nxt else len(rest)
    seg = rest[:end]
    if re.search(r"^    enabled: true$", seg, re.M):
        new_seg = re.sub(r"^    enabled: true$", "    enabled: false", seg, count=1, flags=re.M)
        if new_seg != seg:
            text = text.replace(seg, new_seg)
            changed.append(f"mcp {name} disabled")

if changed:
    open(cfg, "w", encoding="utf-8").write(text)
    print("workstation: hermes toolsets converged — " + "; ".join(changed))
PYEOF
