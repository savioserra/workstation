---
name: tmux
description: Drive tmux panes — list, read, type, paste and watch pane output without polling. Use when operating terminal panes, driving interactive programs (REPLs, ssh, TUIs) or waiting on pane output.
---

# tmux

The dedicated `tmux_*` tools (tmux_ps, tmux_read, tmux_type, tmux_key, tmux_paste, tmux_hex, tmux_run, tmux_split, tmux_kill, tmux_watch) are the first surface for every pane action: they are deferred tools — surface with `tool_search`, load schemas with `tool_describe`, invoke with `tool_call`. `scripts/tmuxctl` (this skill's directory, run through the terminal) is the fallback when a needed verb or flag is missing from the tools. Target panes by ID (`%3` — from `tmux_ps` / `tmuxctl ps`), never by index. Every verb takes `-L <socket>` for scratch servers.

## Verbs

| Verb | Shape | Does |
|---|---|---|
| `ps` | `tmuxctl ps [-a]` | one line per pane: id, session:win.idx, command, title, size, dead |
| `read` | `tmuxctl read %3 [-S n] [-e]` | snapshot + cursor + copy-mode state; `-S` scrollback, `-e` keeps SGR |
| `type` | `tmuxctl type %3 TEXT` | literal text into the pane — never submits |
| `key` | `tmuxctl key %3 Enter` / `C-c` / `Escape` | named keys; the only submit path |
| `paste` | `tmuxctl paste %3 < block` | bracketed paste from stdin — multiline blocks into REPLs/shells |
| `hex` | `tmuxctl hex %3 1b 5b 31 3b 32 75` | raw byte sequences key names cannot express |
| `run` | `tmuxctl run %3 'cmd' [--timeout N] [--await RE] [--no-wait]` | submit and wait: yields output tail + `--- exit N ---` at the `ws-done` completion marker (invisible OSC output; the pane echoes only the short `ws-go <id> ; cmd ; ws-done <id> $?` tokens; a pane whose shell lacks the helpers answers its first run with exit `5` (finished, exit code unknown) and is remembered in the `@tmuxctl_helpers` pane option — later runs there carry inline markers and report exit codes); `--await RE` returns when the pane prints RE (session keeps running — the interactive-launch path); `--no-wait` fires and forgets; POSIX panes only (cmd.exe: `--no-wait` + read) |
| `split` | `tmuxctl split %3 [-H] [-l SIZE]` | split the pane's window, prints the new pane id |
| `kill` | `tmuxctl kill %3 [%4 ...]` | kill panes — refuses this agent's own pane |
| `watch` | `tmuxctl watch %3 --until REGEX [--idle N] [--timeout N] [--all] [--raw]` | streams pane output by tmux control-mode push — zero polling |

## Watch semantics

- exit `0` — `--until` matched (matches echoed under `--- matched ---`)
- exit `3` — `--idle` seconds of silence in the watched pane
- exit `124` — `--timeout` elapsed
- `--all` covers every pane of the session (lines carry the `%id` prefix); the watch rides one control-mode client attached to the target pane's session
- tmux's own copy/choose-mode output is not delivered by control mode — leave copy mode before watching
- a control client receives output from attach onward: attach the watcher before submitting the command whose output you await (`type` → `watch` → `key Enter`), or build a delay into the command

## Laws

1. Read before act: `read` the pane immediately before typing into it — prompts resolve, earlier sends may have landed.
2. Enter is always a separate call: `type` cannot submit; `key Enter` submits. `run` is the only composed submit.
3. Blocks go through `paste`, never `type` — line-by-line submission is a paste of a block, not N typed lines.
4. Scratch work on scratch servers: `-L <name>` and `kill-server` between rounds; the default socket is the operator's live surface.
5. Before any write on a shared server (source-file, kill-session, run-shell), list clients first.
6. Never kill the pane this agent runs in (`$TMUX_PANE`).
7. Long-tail verbs stay raw `tmux` (respawn-pane, swap-pane, resize-pane, select-layout) — these laws still apply.
