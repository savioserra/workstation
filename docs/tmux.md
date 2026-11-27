# tmux reference

| Property | Value |
| --- | --- |
| Hosts | Linux, macOS |
| Main target | `~/.tmux.conf` and the `~/.config/tmux/tmux.conf` symlink |
| Status bar | tmux2k; the colors from the workstation theme pick ([theme](theme.md)), upstream `onedark` as the fallback |
| Implementation | the terminal domain's tmux member (`modules/terminal/tmux/tmux.nix`, payload co-located) |
| Plugin root | `~/.tmux/plugins/` |

## Core settings

| Setting | Value |
| --- | --- |
| `status-position` | `bottom` |
| `pane-border-status` | `top` — a label on every pane's top border |
| `pane-border-format` | tmux's default — index (reversed on the active pane), the pane's terminal title in quotes, then the running command and directory; the float, zoom and close buttons anchor right with the mouse on |
| `popup-border-lines`, `menu-border-lines` | `rounded` |
| `escape-time` | `10` |
| `focus-events` | `on` |
| `mouse` | `on` |
| `default-terminal` | `tmux-256color` |
| `terminal-features[100]` | `xterm-256color:RGB` |
| `scroll-on-clear` | `off` inside `%if "#{>=:#{version},3.5}"` — the guard keeps the conf parse-safe on tmux releases without the option |
| `@tmux2k-theme` | `onedark` — the fallback palette when no theme pick exists |
| `@tmux2k-bg-main` / `@tmux2k-bg-alt` / `@tmux2k-dark-blue` | `default` — the window no-background slots; the theme pick keeps `default` on dark themes and paints the palette `bg` on light ones |
| `@tmux2k-white` | onedark comment gray — inactive window text; the theme pick's `inactive` |
| Theme pick | `source-file -q ~/.local/state/workstation/theme/current/tmux.conf` after the tmux2k options |
| `@tmux2k-window-list-colors` | `blue dark_blue` — active window = onedark blue text, no background |
| `@tmux2k-window-list-left-sep` / `-right-sep` | empty — the window separator spans style zero characters, so they paint nothing |
| `@tmux2k-right-plugins` | `cpu ram time` — clicking cpu opens btop; ram's popup is pinned to btop too |
| `@tmux2k-time-format` | `%a %H:%M` — no seconds: a seconds clock pins the status bar to a 1Hz re-render |
| Window cycling | root `S-Left` / `S-Right` — `previous-window` / `next-window`, no prefix |
| Shell drain | the `tmux()` wrapper in bash and zsh — tmux takes the terminal for its own prompt, the wrapper reads the reply and hands the terminal back |

Load order:

1. Base tmux settings.
2. The tmux2k options — theme, the right-side plugin list, the btop popup pin and the clock format.
3. The theme pick's `tmux.conf` (`source-file -q`; an absent pick = the onedark fallback).
4. The tmux2k plugin (`run-shell`).

`~/.config/tmux/tmux.conf` is a managed symlink to `~/.tmux.conf` so a tmux
that loads the XDG path after `~/.tmux.conf` cannot let a distribution or
desktop default override the managed theme.

## Plugin pins

| Plugin | Commit |
| --- | --- |
| `2KAbhishek/tmux2k` | `d8c5c2924c557835f984dd44eb71315b897bc4f5` |

The pin is declared in `modules/terminal/tmux/tmux.nix` (owner/repo/rev/hash
literals — one pin, one owner) and the checkout rides the store:
`~/.tmux/plugins/tmux2k` is a store link, never a hand-placed clone.

## The server skew

| Surface | Behavior |
| --- | --- |
| The activate routine `tmuxServerSkew` | The running server's version and the generation's; a switch never restarts the server (it holds live sessions) |
| A skew | Reported on stderr, the restart left to the operator |

## Verify

`modules/terminal/tmux/verify/tmux.sh` — the binary runs, the managed
config and its XDG symlink are deployed, the plugin checkout is in place, an
isolated server parses the config and carries the tmux2k options.
