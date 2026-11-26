# The cli session toolsets and the disabled MCP servers, converged into
# config.yaml at apply.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
  hermes = config.programs.hermes;
  helpers = import ./packages.nix { inherit pkgs; };
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
      ${helpers.workstation-hermes-toolsets}/bin/workstation-hermes-toolsets \
        "$HOME/.hermes/config.yaml" \
        "${lib.concatStringsSep "," hermes.cliToolsets}" \
        "${lib.concatStringsSep "," hermes.disabledMcpServers}"
    '';
  };
}
