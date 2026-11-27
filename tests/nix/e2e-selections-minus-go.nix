# the go-deselected generation: the routine fixture without the boot
# generation's teardown; an activate probe
{
  workstation.routines.activate.e2eProbe = ''
    mkdir -p "$HOME/.cache" && echo "activate minus-go" >>"$HOME/.cache/e2e-routines.log"
  '';
  workstation.languages = {
    elixir.enable = true;
    node.enable = true;
    typescript.enable = true;
  };
}
