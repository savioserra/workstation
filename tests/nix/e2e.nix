# The live proof driver: `workstation-e2e` runs INSIDE the container E2E's
# throwaway nix container (tests/nix/run-container.sh stages the boot home,
# then invokes this driver). Every step is asserted loud on the log the
# host script greps:
#
#   workstation-e2e: <step> ... ok / FAIL
#   workstation-e2e: OK             (the final marker run-container.sh greps)
#
# The apply step drives the workstation-switch driver with a prebuilt
# activation override (WORKSTATION_SWITCH_HOME_ACTIVATE) — the offline
# form of `home-manager switch`: the evaluation happened at build time
# inside the container, so the override does the two things a switch would
# have done, fully offline:
#   1. run the standalone activation (home files, unit files, profile links)
#   2. register the generation the way `home-manager switch` does
#      (nix-env --set on the home-manager profile) — the driver's receipt
#      reads the generation number from that profile link
{
  lib,
  pkgs,
  writeShellScript,
  writeShellScriptBin,
  self,
  harlequinVersion,
}:
let
  activation = self.checks.x86_64-linux.e2e-home;

  homeActivateMinusGo = writeShellScript "workstation-e2e-home-activate-minus-go" ''
    set -eu
    ${activationMinusGo}/activate
    nix-env --profile "''${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager" \
      --set ${activationMinusGo}
  '';

  activationMinusGo = self.checks.x86_64-linux.e2e-minus-go-home;

  initTools = pkgs.symlinkJoin {
    name = "workstation-e2e-init-tools";
    paths = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.gawk
      pkgs.diffutils
      pkgs.jq
    ];
  };
in
writeShellScriptBin "workstation-e2e" ''
  set -u

  home=/home/e2e
  export HOME=$home
  export PATH=/run/current-system/sw/bin:$PATH

  step() {
    echo "workstation-e2e: $1 ..."
  }

  pass() {
    echo "workstation-e2e: $1 ... ok"
  }

  fail() {
    echo "workstation-e2e: $1 ... FAIL: $2" >&2
    # The failure is the interesting data on a headless proof host: dump
    # the user unit dir to the log before dying.
    ls -la $home/.config/systemd/user/ "$home/.config/systemd/user/default.target.wants" 2>&1 | tail -12 >&2
    exit 1
  }

  # 2. consumer smoke: the launcher shim dispatches, the nvim profile link
  #    resolves
  # the home lane's packages land on the profile PATH; resolve through the
  # known profile locations too so the proof never bets on PATH shape
  find_client() {
    local bin
    bin=$(command -v "$1" 2>/dev/null || true)
    if [ -z "$bin" ]; then
      for bin in "$home/.nix-profile/bin/$1" "/etc/profiles/per-user/e2e/bin/$1" /run/current-system/sw/bin/"$1"; do
        [ -x "$bin" ] && { printf '%s\n' "$bin"; return 0; }
      done
      return 1
    fi
    printf '%s\n' "$bin"
  }
  step "launcher shim dispatch (help, usage, unknown verb)"
  shim_bin=$(find_client workstation) \
    || fail "launcher shim dispatch" "workstation is not staged"
  "$shim_bin" help >/dev/null 2>&1 \
    || fail "launcher shim dispatch" "workstation help failed"
  "$shim_bin" frobnicate >/dev/null 2>&1 &&
    fail "launcher shim dispatch" "an unknown verb must fail (exit 2)"
  rc=0
  "$shim_bin" frobnicate >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] \
    || fail "launcher shim dispatch" "unknown verb must exit 2 (got $rc)"
  pass "launcher shim dispatch"

  step "nvim profile link"
  # the container stages the boot home before the driver runs; the bounded
  # settle turns a lost staging race (if one ever returns) from a FAIL
  # into a loud wait
  settle=0
  while [ $settle -lt 90 ]; do
    [ -x "$home/.local/bin/nvim" ] && [ -r "$home/.config/nvim/lua/languages/profile.lua" ] && break
    settle=$((settle + 3))
    sleep 3
  done
  [ -x "$home/.local/bin/nvim" ] \
    || fail "nvim profile link" "$home/.local/bin/nvim is not executable"
  pass "nvim profile link"

  step "deployed language profile"
  prof="$home/.config/nvim/lua/languages/profile.lua"
  [ -r "$prof" ] \
    || fail "deployed language profile" "$prof missing (the composition gap closed natively)"
  grep -q '\["id"\] = "standard"' "$prof" \
    || fail "deployed language profile" "the standard entry is missing from $prof"
  grep -q 'lazyvim.plugins.extras.lang.go' "$prof" \
    || fail "deployed language profile" "the go entry is missing from $prof"
  grep -q 'lazyvim.plugins.extras.lang.elixir' "$prof" \
    || fail "deployed language profile" "the elixir entry is missing from $prof"
  grep -q 'lazyvim.plugins.extras.lang.typescript' "$prof" \
    || fail "deployed language profile" "the typescript entry is missing from $prof (the persona's selection fixture pins it)"
  [ -r "$home/.config/nvim/lua/languages/plugins/elixir.lua" ] \
    || fail "deployed language profile" "the elixir plugin module did not deploy"
  [ -r "$home/.config/nvim/lua/languages/plugins/typescript.lua" ] \
    || fail "deployed language profile" "the typescript plugin module did not deploy"
  [ -r "$home/.config/nvim/lua/languages/plugins/go.lua" ] \
    || fail "deployed language profile" "the go plugin module did not deploy"
  pass "deployed language profile"

  step "lazy-lock merge (seeded from the pinned baseline)"
  lock="$home/.config/nvim/lazy-lock.json"
  [ -s "$lock" ] \
    || fail "lazy-lock merge" "$lock was not seeded by the merge activation"
  grep -q 'oasis.nvim' "$lock" \
    || fail "lazy-lock merge" "$lock does not carry the pinned baseline"
  pass "lazy-lock merge"

  # the composed profile.lua is a lua chunk: nvim headless exits 0 with
  # every language module composed (content greps miss E5113 on require).
  # First boot restores the lock's plugins; the bound stops a clone storm.
  step "nvim boots headless with the languages composed"
  nvim_boot() {
    if command -v timeout >/dev/null 2>&1; then
      timeout 600 "$home/.local/bin/nvim" --headless +qa
    else
      "$home/.local/bin/nvim" --headless +qa
    fi
  }
  nvim_boot >/dev/null 2>"$home/.cache/e2e-nvim-boot.err" \
    || fail "nvim boots headless" "nvim --headless +qa exited non-zero (see .cache/e2e-nvim-boot.err in the persona home)"
  pass "nvim boots headless with the languages composed"

  # 2b. the agent domain: the pinned runtime stack and the linked skills
  step "agent runtime stack (launcher, interpreter, pin manifest)"
  [ -x "$home/.local/bin/hermes" ] \
    || fail "agent runtime stack" "$home/.local/bin/hermes is not executable"
  [ -f "$home/.local/opt/hermes/bin/hermes" ] \
    || fail "agent runtime stack" "$home/.local/opt/hermes/bin/hermes missing"
  [ -x "$home/.local/opt/hermes/python/bin/python3" ] \
    || fail "agent runtime stack" "the pinned interpreter did not deploy"
  grep -Eq '"engine":\{"rev":"[0-9a-f]{40}' "$home/.local/opt/hermes/pin.json" 2>/dev/null \
    || fail "agent runtime stack" "the deployed pin manifest carries no engine rev"
  pass "agent runtime stack"

  step "hermes pane resume helper staged beside the launcher"
  [ -x "$(dirname "$(readlink -f "$home/.local/bin/hermes")")/hermes-pane-resume" ] \
    || fail "pane resume" "hermes-pane-resume is not beside the launcher"
  pass "pane resume"

  step "agent skills served as declared entry symlinks"
  [ -L "$home/.hermes/skills/secrets" ] \
    || fail "agent skills" "$home/.hermes/skills/secrets is not the declared entry symlink"
  case "$(readlink "$home/.hermes/skills/secrets")" in
    /nix/store/*) ;;
    *) fail "agent skills" "$home/.hermes/skills/secrets does not resolve into the store" ;;
  esac
  [ -r "$home/.hermes/skills/secrets/SKILL.md" ] \
    || fail "agent skills" "$home/.hermes/skills/secrets/SKILL.md unreadable through the symlink"
  [ -L "$home/.hermes/skills/hsql" ] \
    || fail "agent skills" "$home/.hermes/skills/hsql is not the declared entry symlink"
  [ -r "$home/.hermes/skills/hsql/SKILL.md" ] \
    || fail "agent skills" "$home/.hermes/skills/hsql/SKILL.md unreadable through the symlink"
  # the explicit profile targeting: the named profile sees the same
  # declared entries
  [ -L "$home/.hermes/profiles/fresh/skills/secrets" ] \
    || fail "agent skills" "the named profile's skills dir carries no secrets entry"
  [ -r "$home/.hermes/profiles/fresh/skills/secrets/SKILL.md" ] \
    || fail "agent skills" "the named profile's secrets entry is unreadable"
  pass "agent skills"

  step "hsql skill version matches the derivation (the hsql precedent)"
  # the skill tree IS this generation's harlequin build — the fully
  # resolved store path carries the derivation version the pin ships (HM
  # may link through its files tree; resolve to the end)
  case "$(readlink -f "$home/.hermes/skills/hsql")" in
    *hsql-agent-skill-${harlequinVersion}) ;;
    *) fail "hsql skill version" \
      "$home/.hermes/skills/hsql does not resolve into the ${harlequinVersion} skill derivation" ;;
  esac
  pass "hsql skill version"

  step "zellij plane (managed config, resurrection on, a session resurrectable after it ends)"
  zconf="$home/.config/zellij/config.kdl"
  [ -r "$zconf" ] \
    || fail "zellij plane" "$zconf missing"
  grep -qx 'session_serialization true' "$zconf" \
    || fail "zellij plane" "the managed config does not turn session serialization on"
  grep -qx 'serialize_pane_viewport false' "$zconf" \
    || fail "zellij plane" "the managed config does not keep the pane viewport off disk"
  grep -qx 'keybinds preset="unlock-first"' "$zconf" \
    || fail "zellij plane" "the managed config does not select the unlock-first keybinds"
  zellij_bin=$(find_client zellij) || fail "zellij plane" "zellij is not on PATH"
  "$zellij_bin" setup --check >/dev/null 2>&1 \
    || fail "zellij plane" "zellij setup --check rejects the managed config"
  "$zellij_bin" attach --create-background e2e-z >/dev/null 2>&1 \
    || fail "zellij plane" "a background session did not start on the managed config"
  "$zellij_bin" list-sessions --no-formatting 2>/dev/null | grep -q '^e2e-z ' \
    || fail "zellij plane" "the background session is not listed"
  # a save right after the start writes only the metadata: save until the
  # layout lands
  zinfo="''${XDG_CACHE_HOME:-$home/.cache}/zellij/contract_version_1/session_info"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    "$zellij_bin" -s e2e-z action save-session >/dev/null 2>&1
    ls "$zinfo"/*/session-layout.kdl >/dev/null 2>&1 && break
    sleep 0.5
  done
  ls "$zinfo"/*/session-layout.kdl >/dev/null 2>&1 \
    || fail "zellij plane" "the session did not serialize its layout"
  "$zellij_bin" kill-session e2e-z >/dev/null 2>&1 \
    || fail "zellij plane" "the session did not end"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    "$zellij_bin" list-sessions --no-formatting 2>/dev/null | grep -q '^e2e-z .*EXITED' && break
    sleep 1
  done
  "$zellij_bin" list-sessions --no-formatting 2>/dev/null | grep -q '^e2e-z .*EXITED' \
    || fail "zellij plane" "the ended session is not resurrectable"
  "$zellij_bin" delete-session --force e2e-z >/dev/null 2>&1 || true
  pass "zellij plane"

  step "pre-existing rc file moved aside by the first switch"
  grep -qx '# distro bashrc' "$home/.bashrc.hm-backup" 2>/dev/null \
    || fail "pre-existing rc file" "the distro .bashrc was not kept as .bashrc.hm-backup"
  [ -L "$home/.bashrc" ] \
    || fail "pre-existing rc file" ".bashrc is not the managed link"
  pass "pre-existing rc file moved aside by the first switch"

  step "shell init (home-manager programs: eza, starship, direnv, the op env, the editor env)"
  grep -q "alias -- ls='eza -lh'\|alias ls='eza -lh'" "$home/.bashrc" \
    || fail "shell init" ".bashrc carries no eza ls alias"
  grep -q 'starship init bash' "$home/.bashrc" \
    || fail "shell init" ".bashrc carries no starship init"
  grep -q 'starship init zsh' "$home/.zshrc" \
    || fail "shell init" ".zshrc carries no starship init"
  starship_line=$(grep -n 'starship init bash' "$home/.bashrc" | head -n 1 | cut -d: -f1)
  direnv_line=$(grep -n 'direnv.* hook bash' "$home/.bashrc" | head -n 1 | cut -d: -f1)
  [ -n "$direnv_line" ] && [ "$direnv_line" -gt "$starship_line" ] \
    || fail "shell init" "the bash direnv hook does not follow the starship init"
  session_vars=$(grep -o '/nix/store/[^"]*hm-session-vars.sh' "$home/.profile" | head -n 1)
  [ -n "$session_vars" ] && grep -q '/etc/workstation/secrets.env' "$session_vars" \
    || fail "shell init" "the session variables .profile sources carry no op env"
  [ -r "$home/.config/starship.toml" ] \
    || fail "shell init" "the starship config did not deploy"
  [ -d "$home/.local/share/fonts/JetBrainsMonoNerdFont" ] \
    || fail "shell init" "the nerd font tree did not deploy"
  pass "shell init"

  step "tools run (nixpkgs)"
  for t in fd rg lazygit tree-sitter op mise; do
    t_bin=$(find_client "$t") || fail "tools run" "$t is not on PATH"
    "$t_bin" --version >/dev/null 2>&1 \
      || fail "tools run" "$t --version failed at $t_bin"
  done
  mosh_bin=$(find_client mosh) || fail "tools run" "mosh is not on PATH"
  grep -q -- '--server=.*hm-session-vars.sh' "$mosh_bin" \
    || fail "tools run" "mosh at $mosh_bin is not the wrapper carrying the remote session vars"
  "$mosh_bin" --version >/dev/null 2>&1 \
    || fail "tools run" "mosh --version failed through the wrapper"
  pass "tools run"

  step "mise plane (config pins, activation after the direnv hook, installed tools)"
  mise_cfg="$home/.config/mise/config.toml"
  [ -r "$mise_cfg" ] \
    || fail "mise plane" "$mise_cfg missing"
  for pin in 'node = "24.22.2"' 'pnpm = "12.9.0"' 'go = "1.27.3"' 'elixir = "1.20.5-otp-28"'; do
    grep -qF "$pin" "$mise_cfg" \
      || fail "mise plane" "$pin missing from $mise_cfg"
  done
  grep -qF 'version = "28.5.0.8"' "$mise_cfg" \
    || fail "mise plane" "the erlang pin missing from $mise_cfg"
  nv=$(cat "$home/.node-version" 2>/dev/null || true)
  [ "$nv" = "24.22.2" ] \
    || fail "mise plane" ".node-version carries '$nv', expected the node pin"
  grep -q 'mise activate bash' "$home/.bashrc" \
    || fail "mise plane" ".bashrc carries no mise activation"
  grep -q 'mise activate zsh' "$home/.zshrc" \
    || fail "mise plane" ".zshrc carries no mise activation"
  mise_line=$(grep -n 'mise activate bash' "$home/.bashrc" | head -n 1 | cut -d: -f1)
  [ -n "$mise_line" ] && [ "$mise_line" -gt "$direnv_line" ] \
    || fail "mise plane" "the mise activation must follow the direnv hook"
  # exec of the prebuilt toolchains needs a glibc host (nix-ld on NixOS
  # legs) — the lane proves provisioning of the tools whose binaries run
  # here (go, pnpm: static); node's mise probe cannot exec on this image,
  # beam rides prebuilt platforms only (no Ubuntu build answers here)
  [ -x "$home/.local/share/mise/installs/go/1.27.3/bin/go" ] \
    || fail "mise plane" "the mise go install did not provision"
  [ -d "$home/.local/share/mise/installs/pnpm/12.9.0" ] \
    || fail "mise plane" "the mise pnpm install did not provision"
  pass "mise plane (config pins, activation after the direnv hook, installed tools)"

  step "theme plane (rendered themes, the seeded pick, the switcher, hermes and nvim following, the picker)"
  themes="$home/.local/share/workstation/themes"
  pick="$home/.local/state/workstation/theme/current"
  for t in dark light; do
    grep -q "\"appearance\":\"$t\"" "$themes/$t/tokens.json" 2>/dev/null \
      || fail "theme plane" "$themes/$t/tokens.json carries no $t appearance"
  done
  [ -L "$pick" ] \
    || fail "theme plane" "the activation seeded no pick at $pick"
  [ "$(readlink "$pick")" = "$themes/dark" ] \
    || fail "theme plane" "the seeded pick is not the default (dark): $(readlink "$pick")"
  wt=$(find_client workstation-theme) || fail "theme plane" "workstation-theme is not on PATH"
  "$wt" light >/dev/null \
    || fail "theme plane" "workstation-theme light failed"
  [ "$("$wt" current)" = light ] \
    || fail "theme plane" "the pick did not move to light"
  grep -qx "  background: '#f5f2ea'" "$home/.hermes/skins/workstation-light.yaml" \
    || fail "theme plane" "the hermes light skin did not render from the light tokens"
  grep -q 'config set display.skin "workstation-$THEME"' "$(readlink -f "$wt")" \
    || fail "theme plane" "the pick does not switch the hermes skin"
  out=$("$home/.local/bin/nvim" --headless -c "lua io.stdout:write('BG=' .. vim.o.background .. '\n')" -c 'qa!' 2>/dev/null)
  case "$out" in
    *BG=light*) ;;
    *) fail "theme plane" "nvim did not start on the light pick ($out)" ;;
  esac
  out=$("$home/.local/bin/nvim" --headless -c "lua vim.fn.system({ '$wt', 'dark' }); vim.wait(5000, function() return vim.o.background == 'dark' end, 20); io.stdout:write('LIVE=' .. vim.o.background .. '\n')" -c 'qa!' 2>/dev/null)
  case "$out" in
    *LIVE=dark*) ;;
    *) fail "theme plane" "a running nvim did not follow the dark pick ($out)" ;;
  esac
  "$wt" light >/dev/null \
    || fail "theme plane" "workstation-theme light failed"
  rc=0
  "$wt" set nope 2>/dev/null || rc=$?
  [ "$rc" = 2 ] \
    || fail "theme plane" "an unknown theme must exit 2 (got $rc)"
  pass "theme plane"

  step "init capture live (placeholders fill, settings survive, the re-init is byte-identical)"
  initlive=/tmp/ws-init
  mkdir -p "$initlive"
  cp -a /workstation/. "$initlive/"
  chmod -R u+w "$initlive"
  mkdir -p "$initlive/hosts/local"
  printf '%s\n' '{"host":"TEMPLATE","user":"TEMPLATE","home":"/home/TEMPLATE","settings":{"workstation":{"foundation":{"shell":{"extras":"stty -ixon"}}}}}' \
    >"$initlive/hosts/local/machine.json"
  init_path=${initTools}/bin:$PATH
  out=$(PATH="$init_path" WORKSTATION_NO_APPLY=1 WORKSTATION_FLAKE="$initlive" "$shim_bin" init) \
    || fail "init capture live" "init on the template fixture failed"
  printf '%s' "$out" | grep -q 'machine captured' \
    || fail "init capture live" "the capture must say it captured"
  grep -q TEMPLATE "$initlive/hosts/local/machine.json" \
    && fail "init capture live" "init must fill every placeholder"
  detected_host=$(PATH="$init_path" uname -n | cut -d. -f1)
  m() { PATH="$init_path" jq -r "$1" "$initlive/hosts/local/machine.json"; }
  [ "$(m .host)" = "$detected_host" ] || fail "init capture live" "init must capture the detected host ($detected_host)"
  [ "$(m .user)" = e2e ] || fail "init capture live" "init must capture the detected user (e2e)"
  [ "$(m .home)" = /home/e2e ] || fail "init capture live" "init must capture the detected home (/home/e2e)"
  [ "$(m .system)" = x86_64-linux ] || fail "init capture live" "init must capture the system"
  [ "$(m .settings.workstation.foundation.shell.extras)" = 'stty -ixon' ] \
    || fail "init capture live" "the settings must survive the capture"
  cp "$initlive/hosts/local/machine.json" "$initlive/machine.converged"
  out=$(PATH="$init_path" WORKSTATION_NO_APPLY=1 WORKSTATION_FLAKE="$initlive" "$shim_bin" init) \
    || fail "init capture live" "the converged re-init failed"
  printf '%s' "$out" | grep -q 'already captured' \
    || fail "init capture live" "the converged re-init must say so"
  PATH="$init_path" cmp -s "$initlive/machine.converged" "$initlive/hosts/local/machine.json" \
    || fail "init capture live" "a converged re-init must leave the file byte-identical"
  rm -rf "$initlive"
  pass "init capture live (placeholders fill, settings survive, the re-init is byte-identical)"

  step "selection verbs live (a writable checkout copy: selected, add, dedup, refusals)"
  live=/tmp/ws-live
  mkdir -p "$live"
  cp -a /workstation/. "$live/"
  chmod -R u+w "$live"
  mkdir -p "$live/hosts/local"
  cp "$live/hosts/template/machine.json" "$live/hosts/local/"
  go_flag() { PATH="$init_path" jq -r '.settings.workstation.languages.go.enable // "unset"' "$live/hosts/local/machine.json"; }
  WORKSTATION_FLAKE=$live WORKSTATION_NO_APPLY=1 "$shim_bin" selected \
    | grep -o '"languages/go":{[^}]*}' | grep -q '"state":"off"' \
    || fail "selection verbs live" "selected must answer the template's off row for languages/go"
  WORKSTATION_FLAKE=$live WORKSTATION_NO_APPLY=1 "$shim_bin" add languages/go >/dev/null \
    || fail "selection verbs live" "add languages/go failed"
  [ "$(go_flag)" = true ] || fail "selection verbs live" "add did not set the flag in the machine file"
  WORKSTATION_FLAKE=$live WORKSTATION_NO_APPLY=1 "$shim_bin" selected \
    | grep -o '"languages/go":{[^}]*}' | grep -q '"state":"on"' \
    || fail "selection verbs live" "selected must answer on after the add (the report must read the dirty tree)"
  sel_out=$(WORKSTATION_FLAKE=$live WORKSTATION_NO_APPLY=1 "$shim_bin" add languages/go) \
    || fail "selection verbs live" "the repeated add must succeed"
  printf '%s' "$sel_out" | grep -q 'already selected' \
    || fail "selection verbs live" "a repeated add must say so"
  sel_out=$(WORKSTATION_FLAKE=$live WORKSTATION_NO_APPLY=1 "$shim_bin" add foundation 2>&1) \
    && fail "selection verbs live" "add foundation must refuse"
  printf '%s' "$sel_out" | grep -q 'baseline — always on' \
    || fail "selection verbs live" "the baseline refusal must say so"
  WORKSTATION_FLAKE=$live WORKSTATION_NO_APPLY=1 "$shim_bin" remove languages/go >/dev/null \
    || fail "selection verbs live" "remove languages/go failed"
  [ "$(go_flag)" = unset ] || fail "selection verbs live" "the removed flag must leave the file"
  unset shim_bin
  pass "selection verbs live (a writable checkout copy: selected, add, dedup, refusals)"

  step "apply-driven switch (the removal apply: go deselected, next generation)"
  staged_switch=$(find_client workstation-switch) \
    || fail "apply-driven switch" "the staged switch driver is not on PATH"
  switch_out=$(WORKSTATION_SWITCH_HOME_ACTIVATE="${homeActivateMinusGo}" "$staged_switch" apply) \
    || fail "apply-driven switch" "the driver failed (switch or receipt)"
  unset WORKSTATION_SWITCH_HOME_ACTIVATE
  pass "apply-driven switch (the removal apply: go deselected, next generation)"

  step "the removal: go left the profile and the mise config, the rest rides"
  grep -q 'lazyvim.plugins.extras.lang.go' "$prof" \
    && fail "the removal" "the go profile entry survived the go-deselected generation"
  grep -q 'lazyvim.plugins.extras.lang.elixir' "$prof" \
    || fail "the removal" "the elixir entry must ride the go-deselected generation"
  # the rendered plugin file leaves with its selection: the previous
  # generation deployed go.lua, this tree drops it — the editor deploy's
  # managed-path prune must take it from the live tree
  [ ! -e "$home/.config/nvim/lua/languages/plugins/go.lua" ] \
    || fail "the removal" "the go plugin module survived the go-deselected apply (the managed-path prune died)"
  if grep -qF 'go = "1.27.3"' "$mise_cfg"; then
    fail "the removal" "the go pin survived the go-deselected generation"
  fi
  grep -qF 'node = "24.22.2"' "$mise_cfg" \
    || fail "the removal" "the node pin must ride the go-deselected generation"
  [ -r "$home/.node-version" ] \
    || fail "the removal" ".node-version must ride the go-deselected generation"
  pass "the removal: go left the profile and the mise config, the rest rides"

  step "nvim still boots after the removal"
  nvim_boot >/dev/null 2>"$home/.cache/e2e-nvim-boot-removal.err" \
    || fail "nvim still boots after the removal" "nvim --headless +qa exited non-zero (see .cache/e2e-nvim-boot-removal.err in the persona home)"
  pass "nvim still boots after the removal"

  step "the theme pick survives the apply"
  [ "$("$wt" current)" = light ] \
    || fail "the theme pick survives the apply" "the apply moved the pick to $("$wt" current)"
  pass "the theme pick survives the apply"

  step "shell lane: the operator extras close the rc files, the editor env speaks in a login shell"
  command -v bash >/dev/null 2>&1 \
    || fail "shell lane" "bash is absent — the login-shell editor-env smoke cannot run"
  for rc in .bashrc .zshrc; do
    last_line=$(grep -v '^[[:space:]]*$' "$home/$rc" | tail -n 1)
    [ "$last_line" = "stty -ixon" ] \
      || fail "shell lane" "$rc does not end with the persona's extras line (last: '$last_line')"
  done
  EDITOR_smoke=$(HOME="$home" bash -lc 'printf %s "$EDITOR"') \
    || fail "shell lane" "a fresh login shell failed to start (the editor-env smoke died)"
  [ "$EDITOR_smoke" = nvim ] \
    || fail "shell lane" "a fresh login shell carries EDITOR='$EDITOR_smoke', expected nvim"
  pass "shell lane"

  # 4. the switch receipt: the driver's tail appended the generation line
  #    to the state tree's switch.log (the daemon journal is gone with the
  #    daemon)
  step "switch receipt in switch.log"
  # the fresh-host form: the first apply on a bare home receipts
  # "generation 1 applied (no prior generation)"; a re-apply receipts the
  # rollback-available form. Either way the generation line must exist —
  # the switch ran and the receipt closed it.
  grep -Eq "generation [0-9]+ applied \(" \
    "$home/.local/state/workstation/switch.log" 2>/dev/null \
    || fail "switch receipt" "no 'generation N applied' line in switch.log"
  pass "switch receipt in switch.log"

  # 5. the staged client: the launcher and the write driver, no repo copy
  step "staged client (launcher, switch driver, no flake snapshot)"
  [ ! -e "$home/.local/opt/workstation/flake" ] \
    || fail "staged client" "the generation still stages a flake snapshot"
  command -v workstation-switch >/dev/null 2>&1 \
    || [ -x "$home/.nix-profile/bin/workstation-switch" ] \
    || [ -x "/etc/profiles/per-user/e2e/bin/workstation-switch" ] \
    || fail "staged client" "the workstation-switch driver is not staged"
  pass "staged client (launcher, switch driver, no flake snapshot)"

  step "rollback lane (the previous generation, the after-rollback routine)"
  rb_out=$("$staged_switch" rollback) \
    || fail "rollback lane" "workstation-switch rollback failed"
  PATH="$init_path" tail -n 1 "$home/.local/state/workstation/switch.log" | grep -Eq 'generation [0-9]+ applied \(' \
    || fail "rollback lane" "the rollback wrote no receipt line"
  pass "rollback lane (the previous generation, the after-rollback routine)"

  echo "workstation-e2e: OK"
''
