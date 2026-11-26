# The agent domain's helper programs: the payload scripts with their tools
# in the closure (PATH-independent).
#
# | Program | Consumer |
# | --- | --- |
# | workstation-hermes-toolsets | the toolsets ensure (programs.hermes.cliToolsets) |
{ pkgs }:
let
  ws = import ../../nix/lib/payload.nix {
    inherit pkgs;
    inherit (pkgs) lib;
  };
in
{
  workstation-hermes-toolsets = ws.script {
    name = "workstation-hermes-toolsets";
    inputs = [ pkgs.python3 ];
    file = ./files/hermes-toolsets.sh;
  };
}
