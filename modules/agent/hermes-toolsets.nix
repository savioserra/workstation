# The cli session toolsets and the disabled MCP servers, converged into
# config.yaml at apply by workstation-hermes-toolsets (also a flake package).
{ wsLib, ... }:
let
  toolsets =
    pkgs:
    (wsLib.payload {
      inherit pkgs;
      inherit (pkgs) lib;
    }).script
      {
        name = "workstation-hermes-toolsets";
        inputs = [ pkgs.python3 ];
        file = ./files/hermes-toolsets.sh;
      };
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages.workstation-hermes-toolsets = toolsets pkgs;
    };

  flake.modules.homeManager.agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ws = wsLib.capability { inherit config lib pkgs; };
      hermes = config.programs.hermes;
    in
    {
      options.programs.hermes = {
        cliToolsets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "browser"
            "clarify"
            "code_execution"
            "computer_use"
            "connections"
            "context_engine"
            "cronjob"
            "delegation"
            "file"
            "memory"
            "session_search"
            "skills"
            "terminal"
            "todo"
            "vision"
            "web"
          ];
          description = "The cli session toolsets config.yaml carries — converged by the toolsets ensure; per-session divergence goes through this option, not hand edits.";
        };

        disabledMcpServers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "rea" ];
          description = "MCP servers kept disabled in config.yaml (entries the user added and the ruled surface drops).";
        };
      };

      config = ws.whenOn "agent" {
        home.activation.ensure-hermes-toolsets = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          ${toolsets pkgs}/bin/workstation-hermes-toolsets \
            "$HOME/.hermes/config.yaml" \
            "${lib.concatStringsSep "," hermes.cliToolsets}" \
            "${lib.concatStringsSep "," hermes.disabledMcpServers}"
        '';
      };
    };
}
