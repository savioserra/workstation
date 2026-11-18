"""tmux pane tools — thin registrations over the bundled scripts/tmuxctl."""

import json
import os
import subprocess

TOOLSET = "tmux"
_CTL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts", "tmuxctl")

_PANE = {
    "type": "string",
    "description": "target pane id (%N from tmux_ps), never an index",
}
_SOCKET = {
    "type": "string",
    "description": "tmux -L socket name for scratch servers; omit for the default socket",
}


def _ctl(args, timeout=60):
    try:
        r = subprocess.run(
            [ _CTL, *args ],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "tmuxctl timed out"}
    if r.returncode == 2:
        return {"ok": False, "error": r.stderr.strip() or "usage error"}
    return {
        "ok": r.returncode == 0,
        "rc": r.returncode,
        "output": (r.stdout or "").strip(),
        "error": (r.stderr or "").strip() or None,
    }


def _sock(args, pane_socket):
    return [*args] if not pane_socket else ["-L", pane_socket, *args]


def tmux_ps(args, **kwargs):
    a = ["ps"] + (["-a"] if args.get("all") else [])
    return json.dumps(_ctl(_sock(a, args.get("socket"))))


def tmux_read(args, **kwargs):
    a = ["read", args["pane"]]
    if args.get("scrollback"):
        a += ["-S", str(args["scrollback"])]
    if args.get("escape"):
        a += ["-e"]
    return json.dumps(_ctl(_sock(a, args.get("socket"))))


def tmux_type(args, **kwargs):
    return json.dumps(_ctl(_sock(["type", args["pane"], args["text"]], args.get("socket"))))


def tmux_key(args, **kwargs):
    keys = args.get("keys") or ["Enter"]
    return json.dumps(_ctl(_sock(["key", args["pane"], *keys], args.get("socket"))))


def tmux_paste(args, **kwargs):
    block = args.get("block", "")
    if not block.strip():
        return json.dumps({"ok": False, "error": "block is required (multiline text)"})
    a = _sock(["paste", args["pane"]], args.get("socket"))
    try:
        r = subprocess.run(
            [ _CTL, *a ],
            input=block,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return json.dumps({"ok": False, "error": "tmuxctl timed out"})
    return json.dumps({
        "ok": r.returncode == 0,
        "rc": r.returncode,
        "error": (r.stderr or "").strip() or None,
    })


def tmux_hex(args, **kwargs):
    return json.dumps(_ctl(_sock(["hex", args["pane"], *args["bytes"]], args.get("socket"))))


def tmux_run(args, **kwargs):
    a = ["run", args["pane"], args["command"]]
    timeout = args.get("timeout") or 180
    if args.get("no_wait"):
        a += ["--no-wait"]
        return json.dumps(_ctl(_sock(a, args.get("socket")), timeout=60))
    if args.get("await"):
        a += ["--await", args["await"]]
    a += ["--timeout", str(timeout)]
    return json.dumps(_ctl(_sock(a, args.get("socket")), timeout=timeout + 30))


def tmux_watch(args, **kwargs):
    a = ["watch", args["pane"]]
    if args.get("until"):
        a += ["--until", args["until"]]
    if args.get("idle"):
        a += ["--idle", str(args["idle"])]
    timeout = args.get("timeout") or 30
    a += ["--timeout", str(timeout)]
    if args.get("all"):
        a += ["--all"]
    if args.get("raw"):
        a += ["--raw"]
    return json.dumps(_ctl(_sock(a, args.get("socket")), timeout=timeout + 30))


_PS = {
    "name": "tmux_ps",
    "description": (
        "List tmux panes: id, session:window.index, running command, title, "
        "size, dead flag. Use before any pane action to resolve pane ids (%N). "
        "all=true lists every session; default lists the current session."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "all": {"type": "boolean", "description": "list panes of every session"},
            "socket": _SOCKET,
        },
    },
}

_READ = {
    "name": "tmux_read",
    "description": (
        "Snapshot a tmux pane: visible text plus cursor position, copy-mode "
        "state and scrollback size. Read the pane immediately before typing "
        "into it. scrollback=N adds N lines of history; escape=true keeps "
        "SGR color codes."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "pane": _PANE,
            "scrollback": {"type": "integer", "description": "scrollback lines to include"},
            "escape": {"type": "boolean", "description": "keep SGR escapes in the capture"},
            "socket": _SOCKET,
        },
        "required": ["pane"],
    },
}

_TYPE = {
    "name": "tmux_type",
    "description": (
        "Type literal text into a pane — never submits it. Enter is a "
        "separate tmux_key call; tmux_run is the composed type+Enter."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "pane": _PANE,
            "text": {"type": "string", "description": "literal text (no key names)"},
            "socket": _SOCKET,
        },
        "required": ["pane", "text"],
    },
}

_KEY = {
    "name": "tmux_key",
    "description": (
        "Send named keys to a pane (Enter, C-c, Escape, Tab, Up...). The only "
        "way to submit input. keys=[\"Enter\"] submits a typed line."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "pane": _PANE,
            "keys": {"type": "array", "items": {"type": "string"}, "description": "tmux key names"},
            "socket": _SOCKET,
        },
        "required": ["pane"],
    },
}

_PASTE = {
    "name": "tmux_paste",
    "description": (
        "Bracketed-paste a multiline block into a pane (REPLs, shells, "
        "editors) — lines are held, not submitted. Submit afterwards with "
        "tmux_key Enter when the target expects it."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "pane": _PANE,
            "block": {"type": "string", "description": "the multiline block to paste"},
            "socket": _SOCKET,
        },
        "required": ["pane", "block"],
    },
}

_HEX = {
    "name": "tmux_hex",
    "description": (
        "Send raw bytes to a pane as hex tokens (e.g. 1b 5b 31 3b 32 75) — "
        "escape sequences key names cannot express."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "pane": _PANE,
            "bytes": {"type": "array", "items": {"type": "string"}, "description": "even-length hex tokens"},
            "socket": _SOCKET,
        },
        "required": ["pane", "bytes"],
    },
}

_RUN = {
    "name": "tmux_run",
    "description": (
        "Run a shell command line in a pane and WAIT: by default until "
        "completion — yields the output tail and exit code (--- exit N ---) "
        "when the shell prints the completion marker. With await=REGEX "
        "returns as soon as the regex matches pane output (--- await "
        "matched, still running ---) — use it for interactive launches "
        "(ssh, REPLs): run 'ssh host' with await 'password:|\\$' and act "
        "while the session stays live; full-session wait also works (the "
        "marker fires at logout). no_wait=true submits and returns "
        "immediately. timeout caps the wait (default 180s, rc 124)."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "pane": _PANE,
            "command": {"type": "string", "description": "the command line"},
            "await": {"type": "string", "description": "regex; return when pane output matches (command keeps running)"},
            "timeout": {"type": "number", "description": "wait cap in seconds (default 180)"},
            "no_wait": {"type": "boolean", "description": "submit and return immediately"},
            "socket": _SOCKET,
        },
        "required": ["pane", "command"],
    },
}

_WATCH = {
    "name": "tmux_watch",
    "description": (
        "Watch a pane's output by tmux control-mode push — zero polling. "
        "Streams lines as they arrive; exits 0 when until matches, 3 after "
        "idle silence, 124 at timeout. Attach BEFORE submitting the command "
        "whose output you await (output before attach is not delivered): "
        "tmux_type, then tmux_watch, then tmux_key Enter. all=true watches "
        "every pane of the session with pane-id prefixes."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "pane": _PANE,
            "until": {"type": "string", "description": "regex; exit 0 on first matching line"},
            "idle": {"type": "number", "description": "exit 3 after this many silent seconds"},
            "timeout": {"type": "number", "description": "exit 124 at this many seconds (default 30)"},
            "all": {"type": "boolean", "description": "watch every pane of the session"},
            "raw": {"type": "boolean", "description": "keep SGR escapes in output"},
            "socket": _SOCKET,
        },
        "required": ["pane"],
    },
}

_TOOLS = [
    (_PS, tmux_ps),
    (_READ, tmux_read),
    (_TYPE, tmux_type),
    (_KEY, tmux_key),
    (_PASTE, tmux_paste),
    (_HEX, tmux_hex),
    (_RUN, tmux_run),
    (_WATCH, tmux_watch),
]


def register(ctx) -> None:
    for schema, handler in _TOOLS:
        ctx.register_tool(
            name=schema["name"],
            toolset=TOOLSET,
            schema=schema,
            handler=handler,
        )


__all__ = ["register"]
