# Tool inventory

Platforms: linux x86_64 (WSL counts as linux), macOS arm64.

| Property | Value |
| --- | --- |
| Tool sourcing | the one nixpkgs input (`nixos-unstable`). The remaining pins declare inline in their owning modules: herdr, the tmux/nunchux checkouts (`fetchFromGitHub`), the hermes checkout (flake input), the language toolchains (mise registry pins) |
| Versions | The nixpkgs lock is the version surface (`nix flake update` moves the set). Inline pins move their owning module's row and consumer together |
| Node version | the mise pin in `modules/languages/node/node.nix`; `~/.node-version` derives from the pin (one source) |
| Update unit | The lock (nixpkgs tools) or the owning module's pin row (inline pins), verification, this table |

| Tool | Version | Source | Target | Platforms |
| --- | --- | --- | --- | --- |
| Neovim | 0.12.x | nixpkgs (`modules/editor/editor.nix`) | `.local/bin/nvim`; the language profile composes in the editor module | linux-x86_64, darwin-arm64 |
| Go | 1.27.3 | mise pin (`modules/languages/go/go.nix`) | the mise global config's `[tools]`; installed under `~/.local/share/mise`, on PATH through the cd activation | linux-x86_64, darwin-arm64 |
| Homebrew | 7.0.x | github.com/Homebrew/brew via `nix-homebrew` (`flake.lock`) | the darwin leg installs and pins brew at the default prefix; `homebrew.*` declares its packages | darwin-arm64 |
| Herdr | 0.9.0 | github.com/herdrdev/herdr | The one inline `fetchurl` pin (no nixpkgs coverage); `.local/bin/herdr` from the store derivation | linux-x86_64, darwin-arm64 |
| Node.js | 24.22.2 | mise pin (`modules/languages/node/node.nix`) | the mise global config's `[tools]`; `~/.node-version` derives from the pin | linux-x86_64, darwin-arm64 |
| pnpm | 12.9.0 | mise pin (`modules/languages/typescript/typescript.nix`) | the mise global config's `[tools]`; installed under `~/.local/share/mise` | linux-x86_64, darwin-arm64 |
| Elixir + Erlang | 1.20.5-otp-28 / 28.5.0.8 | mise pins (`modules/languages/elixir/elixir.nix`) | the mise global config's `[tools]`; elixir pinned to an otp-28 prebuilt build (1.18.x ships none); erlang prebuilt platforms only (`compile = false`, never a kerl build) | linux-x86_64, darwin-arm64 |
| ripgrep | 15.2.x | nixpkgs | on PATH via `home.packages` | linux-x86_64, darwin-arm64 |
| fd | 10.5.x | nixpkgs | on PATH via `home.packages` | linux-x86_64, darwin-arm64 |
| eza | 0.23.5 | nixpkgs via Home Manager (`programs.eza`) | `ls` = `eza -lh` | linux-x86_64, darwin-arm64 |
| starship | 1.27.0 | nixpkgs | on PATH; per-shell init + `.config/starship.toml` | linux-x86_64, darwin-arm64 |
| fzf | 0.74.x | nixpkgs | on PATH via `home.packages` | linux-x86_64, darwin-arm64 |
| mosh | 1.4.0 | nixpkgs | `home.packages` in the terminal domain (the `mosh` wrapper's `--server` sources the remote home-manager session vars — profile PATH, `LOCALE_ARCHIVE_2_27`); `programs.mosh.enable` on NixOS legs opens the mosh UDP firewall ports | linux-x86_64, darwin-arm64 |
| lazygit | 0.66.x | nixpkgs | on PATH via `home.packages` | linux-x86_64, darwin-arm64 |
| tree-sitter (CLI) | 0.26.x | nixpkgs | on PATH via `home.packages` | linux-x86_64, darwin-arm64 |
| harlequin + hsql | 2.16.2 | nixpkgs | harlequin + `hsql` in one derivation; the hsql agent skill generated from the derivation at build time | linux-x86_64, darwin-arm64 |
| mise | 2026.10.17 | nixpkgs | the languages domain's runtime manager: the global config (`~/.config/mise/config.toml`, read-only — the members' pins compose `[tools]`), the cd activation in bash/zsh after the direnv hook, the tool installs under `~/.local/share/mise`; project-level pins belong to each repo's `.mise.toml` | linux-x86_64, darwin-arm64 |
| direnv + nix-direnv | 2.36.0 / 3.0.7 | nixpkgs via Home Manager (`programs.direnv`) | `use flake`/`use nix` with the evaluation cache and GC roots; the bash hook follows the prompt init; complements mise: direnv owns repos with a flake/shell.nix, mise owns repos without nix awareness | linux-x86_64, darwin-arm64 |
| 1Password CLI | 2.41.x | nixpkgs (`modules/secrets/secrets.nix`; unfree — the acceptance is `nix/lib/license.nix`) | `op` on PATH via `home.packages` | linux-x86_64, darwin-arm64 |
| Hermes Agent | rev `3b4215785` (v0.23.1) + interpreter `pkgs.python314` | github.com/NousResearch/hermes-agent; nixpkgs (python 3.14.10, the interpreter floor) | Pinned checkout `~/.hermes/hermes-agent` (activation ensure); interpreter at `.local/opt/hermes/python`; launcher at `.local/bin/hermes`; skills as store entry symlinks (`programs.hermes.skills`); extensions into `~/.hermes/plugins`; verify anchor `.local/opt/hermes/pin.json` | linux-x86_64, darwin-arm64 |
| A2A helpers | yq-go 4.45.4, socat 1.8.0.3, curl 8.14.1, jq 1.7.1, newt 0.52.24, tailscale 1.104.x, findutils | nixpkgs (`modules/agent/packages.nix`) | in the closures of `workstation-a2a-converge` (the activation), `workstation-peers` (`workstation peers`), `workstation-fleet` (the fleet service, `workstation fleet`) and `workstation-a2a-token`, never on PATH | linux-x86_64, darwin-arm64 |
| JetBrainsMono Nerd Font | 3.5.0 | nixpkgs (`modules/fonts/fonts.nix`) | linux `.local/share/fonts/JetBrainsMonoNerdFont`; darwin `Library/Fonts/JetBrainsMonoNerdFont`; fontconfig enabled | linux-x86_64, darwin-arm64 |
| nunchux | 3.1.3 | github.com/datamadsen/nunchux | pinned checkout `.tmux/plugins/nunchux` (`fetchFromGitHub`) + the `bin/.platform` marker; package is linux-only | linux-x86_64 |
| tmux | 3.7c | nixpkgs | the tmux member's `home.packages` and the system legs | linux-x86_64, darwin-arm64 |
| btop | 1.4.7 | nixpkgs | the terminal domain (`home.packages`, every leg); the system legs (NixOS, darwin) | linux-x86_64, darwin-arm64 |
| TPM plugin set | pinned commits | github.com/tmux-plugins/tpm, github.com/2KAbhishek/tmux2k, github.com/tmux-plugins/tmux-yank, github.com/tmux-plugins/tmux-resurrect, github.com/christoomey/vim-tmux-navigator | pinned store checkouts `~/.tmux/plugins/<name>` | linux-x86_64, darwin-arm64 |

## Pin maintenance

The nixpkgs lock is the version surface: `nix flake update` moves the set.
Inline pins declare in their owning
modules — one pin, one owner, one surface; a bump moves the row, its hash
and the consumer together. The agent's verify lane anchors on the
deployed `.local/opt/hermes/pin.json`.

## Host prerequisites

- **nix** with flakes enabled — host-owned on standalone-HM hosts,
  platform-managed on NixOS and nix-darwin.
- **tailscaled** — provisioned by the substrate: the `workstation-tailscaled`
  systemd unit on standalone-HM linux hosts (another tailscale install
  stops the provision, named);
  `services.tailscale` on NixOS-WSL and nix-darwin.
- **whiptail** — ships with the substrate (`pkgs.newt`); a bare box before
  its first switch falls back to the detected identity values.

## Not managed here

| Tool | Why | Where it's handled |
| --- | --- | --- |
| Git on Linux | Distro-provided; no first-party static git passes the acquisition audit | Distro install; nix hosts carry git in the host configuration |
| C compiler/build tools, Linux fontconfig, macOS CLT | Build and font-verification prerequisites | User or CI image |
| ShellCheck | CI validation tool | `.github/scripts/check.sh` |
| 1Password desktop app + session | Interactive authentication is outside source state | Official app, CLI integration, interactive sign-in |
| Mason-installed LSP servers/formatters/linters | Neovim-internal | `mason-lock.json` — see [Neovim](nvim.md) |
| lazy.nvim plugins | Neovim-internal | `lazy-lock.json` — see [Neovim](nvim.md) |
