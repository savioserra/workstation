# Theme capability

One palette source for every workstation surface that renders color, picked
at run time. Owned by `modules/theme/`.

```bash
workstation theme              # the current pick
workstation theme list         # every theme, the pick starred
workstation theme light        # pick: applies at once, kept across applies
```

## Themes

| Theme | File | Appearance | Source |
| --- | --- | --- | --- |
| `dark` | `modules/theme/themes/dark.nix` | dark | Starlight — the oasis.nvim starlight palette |
| `light` | `modules/theme/themes/light.nix` | light | Starlight light — the `light_3` sibling (upstream default intensity) |

- A theme: `{ description; appearance = "dark" | "light"; palette.<role> = "#rrggbb"; ansi.<color> = "#rrggbb" | null; }` — plain nix data.
- `ansi`: the 16 terminal colors (`black` … `brightwhite`) over the theme's canvas, applied to tmux panes; `null` (dark) keeps the terminal's own. `light` ships soft hues at ≥ 4.5:1 on its `bg`.
- `workstation.theme.themes.<name>`: a typed submodule — an unknown role, a missing role or a non-hex value fails the eval.
- Presets merge at `mkDefault` per leaf: a machine overrides one role (`settings.workstation.theme.themes.dark.palette.accent`) or adds a theme.
- `workstation.theme.default` (`dark`): the theme linked when no live pick exists.

## Roles

Roles are the API, values are data; consumers reference role names, never a literal color.

| Option | Maps | Consumed by |
| --- | --- | --- |
| `themes.<name>.palette` | role → `#rrggbb`, per theme | rendered consumer files, `tokens.json` readers |

Roles: `accent`, `ok`, `warn`, `err`, `chrome` (muted chrome/borders), `text`,
`shortcut` (key-cap letters), `selected_bg`/`selected_fg`, `inactive`
(dimmed chrome), `ramp_start`/`ramp_mid`/`ramp_end` (magnitude ramp), `bg`
(canvas), `muted` (dim text).

## Deployed state

| Path | Owner | Content |
| --- | --- | --- |
| `~/.local/share/workstation/themes/<name>/tokens.json` | the generation | `name`, `appearance`, `palette`, `ansi` (16 colors in index order, or `null`) |
| `~/.local/share/workstation/themes/<name>/<consumer file>` | the generation | each consumer's render of that theme |
| `~/.local/state/workstation/theme/current` | the pick | link → `…/themes/<name>`; consumers read through it |

- The activation seeds `current` with the default only when no live pick exists (first apply, or a pick the generation dropped), then runs every consumer's reload.
- `workstation theme <name>`: re-links `current` atomically, then runs every consumer's reload. Nothing polls.

## Consumers

A domain contributes through `workstation.theme.consumers.<name>`, guarded by `ws.whenOn "theme"`:

| Field | Shape |
| --- | --- |
| `file` | path inside each theme dir |
| `render` | `theme: text`; the theme carries `name`, `appearance`, `palette` |
| `reload` | shell lines run after a pick and after every apply |

| Surface | Reads | Mechanism |
| --- | --- | --- |
| nunchux picker | — | `menu:theme` + one `app:theme/<name>` entry per theme (`workstation-theme set <name>`), the pick as the menu status |
| tmux | palette, ansi | `consumers.tmux`: `tmux.conf` per theme — tmux2k colors, borders, messages; light themes paint the pane and popup canvas; `ansi` → `pane-colours` ([tmux](tmux.md)) |
| nvim | appearance | `tokens.json` through the pick sets `vim.o.background` for oasis.nvim, live via a directory watch ([nvim](nvim.md)) |
| nunchux colors | palette | `consumers.nunchux`: `nunchux.conf` per theme — the full launcher config, `fzf_colors` from the palette unless `workstation.terminal.nunchux.settings.fzf_colors` is set; `~/.config/nunchux/config` links through the pick, read per launch |
| herdr | terminal-following | documented canonical choice only: `[theme] name = "terminal"`, `auto_switch = true` ([herdr](herdr.md)) |
