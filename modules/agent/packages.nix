# The agent domain's helper programs: the payload scripts with their tools
# in the closure (PATH-independent).
#
# | Program | Consumer |
# | --- | --- |
# | workstation-a2a-converge | the A2A activation (programs.hermes.a2a) |
# | workstation-a2a-token | the pair-token store (stdin value) for peers and the fleet |
# | workstation-peers | `workstation peers` — the hub over the tailnet's agents |
# | workstation-fleet | the fleet member service and `workstation fleet` joins |
{ pkgs }:
let
  ws = import ../../nix/lib/payload.nix {
    inherit pkgs;
    inherit (pkgs) lib;
  };
  workstation-a2a-token = ws.script {
    name = "workstation-a2a-token";
    inputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    file = ./files/a2a-token.sh;
  };
in
{
  inherit workstation-a2a-token;

  workstation-a2a-converge = ws.script {
    name = "workstation-a2a-converge";
    inputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.tailscale
      pkgs.yq-go
    ];
    file = ./files/a2a-converge.sh;
  };

  workstation-peers = ws.script {
    name = "workstation-peers";
    inputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.newt
      pkgs.socat
      pkgs.tailscale
      workstation-a2a-token
    ];
    file = ./files/a2a-peers.sh;
  };

  workstation-fleet = ws.script {
    name = "workstation-fleet";
    inputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.socat
      pkgs.tailscale
      workstation-a2a-token
    ];
    file = ./files/a2a-fleet.sh;
  };

  workstation-hermes-toolsets = ws.script {
    name = "workstation-hermes-toolsets";
    inputs = [ pkgs.python3 ];
    file = ./files/hermes-toolsets.sh;
  };

  # the tmuxctl run markers: short tokens the pane echoes instead of the
  # inline printf wrapper
  ws-go = pkgs.writeShellScriptBin "ws-go" ''
    printf '\033]7777;tmuxctl:%s:start\007' "$1"
  '';

  ws-done = pkgs.writeShellScriptBin "ws-done" ''
    printf '\033]7777;tmuxctl:%s:end:%s\007' "$1" "$2"
  '';
}
