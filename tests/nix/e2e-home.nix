# The E2E persona's declared home — the ONE body both consumers import:
# the container E2E's boot home and the standalone e2e@container
# configuration (the home leg) that the apply-driven switch applies. Shared so
# the boot plane and the apply target can never drift.
{ ... }:
{
  home.username = "e2e";
  home.homeDirectory = "/home/e2e";
  workstation.switch.homeAttr = "e2e@container";
  programs.hermes.skills.secrets.profiles = [
    "default"
    "fresh"
  ];
  programs.hermes.skills.hsql.profiles = [
    "default"
    "fresh"
  ];
  workstation.foundation.shell.extras = "stty -ixon";
  # the routine fixture both generations carry: a teardown no switch runs
  workstation.routines.teardown.e2eKept = ''
    mkdir -p "$HOME/.cache" && echo "teardown e2eKept" >>"$HOME/.cache/e2e-routines.log"
  '';
}
