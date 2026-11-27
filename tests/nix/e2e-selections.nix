# the boot generation: every language, the routine fixture (a teardown the
# go-deselected generation lacks, recording the live generation it ran
# against; an activate probe)
{
  workstation.routines = {
    teardown.e2eGone = ''
      live=$(readlink -f "''${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager")
      mkdir -p "$HOME/.cache" && echo "teardown e2eGone $live" >>"$HOME/.cache/e2e-routines.log"
    '';
    activate.e2eProbe = ''
      mkdir -p "$HOME/.cache" && echo "activate boot" >>"$HOME/.cache/e2e-routines.log"
    '';
  };
  workstation.languages = {
    elixir.enable = true;
    go.enable = true;
    node.enable = true;
    typescript.enable = true;
  };
}
