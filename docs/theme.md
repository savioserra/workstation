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

- A theme: `{ description; appearance = "dark" | "light"; palette.<role> = "#rrggbb"; }` — plain nix data.
- `workstation.theme.themes.<name>`: a typed submodule — an unknown role, a missing role or a non-hex value fails the eval.
- Presets merge at `mkDefault` per leaf: a machine overrides one role (`settings.workstation.theme.themes.dark.palette.accent`) or adds a theme.
- `workstation.theme.default` (`dark`): the theme linked when no live pick exists.

## Layers

Roles are the API, values are data; consumers reference role names, never a literal color or slot name.

| Layer | Option | Maps | Consumed by |
| --- | --- | --- | --- |
| palette | `themes.<name>.palette` | role → `#rrggbb`, per theme | rendered consumer files, `tokens.json` readers |
| slots | `workstation.theme.slots` | role → ANSI named color (16 names + `default`), shared | terminal-following surfaces (nunchux fzf colors) |

Roles: `accent`, `ok`, `warn`, `err`, `chrome` (muted chrome/borders), `text`,
`shortcut` (key-cap letters), `selected_bg`/`selected_fg`, `inactive`
(dimmed chrome), `ramp_start`/`ramp_mid`/`ramp_end` (magnitude ramp); the
palette adds `bg` and `muted`.

## Deployed state

| Path | Owner | Content |
| --- | --- | --- |
| `~/.local/share/workstation/themes/<name>/tokens.json` | the generation | `name`, `appearance`, `palette`, `slots` |
| `~/.local/share/workstation/themes/<name>/<consumer file>` | the generation | each consumer's render of that theme |
| `~/.local/state/workstation/theme/current` | the pick | link → `…/themes/<name>`; consumers read through it |

- The activation seeds `current` with the default only when no live pick exists (first apply, or a pick the generation dropped), then runs every consumer's reload.
- `workstation theme <name>`: re-links `current` atomically, then runs every consumer's reload. Nothing polls.

## Consumers

A domain contributes through `workstation.theme.consumers.<name>`, guarded by `ws.whenOn "theme"`:

| Field | Shape |
| --- | --- |
| `file` | path inside each theme dir |
| `render` | `theme: text`; the theme carries `name`, `appearance`, `palette`, `slots` |
| `reload` | shell lines run after a pick and after every apply |

| Surface | Layer | Mechanism |
| --- | --- | --- |
| nunchux picker | — | `menu:theme` + one `app:theme/<name>` entry per theme (`workstation-theme set <name>`), the pick as the menu status |
| tmux | palette | `consumers.tmux`: `tmux.conf` per theme — tmux2k colors, borders, messages; light themes paint the pane canvas ([tmux](tmux.md)) |
| nvim | appearance | `tokens.json` through the pick sets `vim.o.background` for oasis.nvim, live via a directory watch ([nvim](nvim.md)) |
| nunchux colors | slots | `workstation.terminal.nunchux.settings.fzf_colors` |
| herdr | terminal-following | documented canonical choice only: `[theme] name = "terminal"`, `auto_switch = true` ([herdr](herdr.md)) |
