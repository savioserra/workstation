# The languages domain: the members are the granularity; the domain owns the
# mise plane — the global config (the members' pins merge into its [tools]
# table), the cd activation and the install.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
  cfg = config.workstation.languages;
  mise = lib.getExe pkgs.mise;
  bashCompletion = pkgs.runCommand "mise-bash-completion.bash" { } ''
    ${mise} completion bash --include-bash-completion-lib > $out
  '';
in
ws.capability [ "languages" ] {
  description = "the language toolchains";
  default = true;
  options.tools = lib.mkOption {
    type = lib.types.attrsOf (lib.types.either lib.types.str (lib.types.attrsOf lib.types.anything));
    default = { };
    description = "mise tool pins merged from the enabled members into the global config's [tools] table.";
  };
  config = {
    programs.mise = {
      enable = true;
      # the domain owns placement: the activation rides after the direnv
      # hook, so mise tools keep PATH precedence over later rc lines
      enableBashIntegration = false;
      enableZshIntegration = false;
      globalConfig = lib.mkIf (cfg.tools != { }) { tools = cfg.tools; };
    };

    programs.bash.initExtra = lib.mkOrder 1990 ''
      eval "$(${mise} activate bash)"
      source ${bashCompletion}
    '';
    programs.zsh.initContent = lib.mkOrder 1990 ''
      eval "$(${mise} activate zsh)"
    '';

    # best-effort at apply: mise's auto-install on use is the backstop
    home.activation.mise-install = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if ${mise} install --yes >/dev/null 2>&1; then
        echo "workstation: mise tools installed"
      else
        echo "workstation: mise install incomplete — run 'mise install' for the remainder" >&2
      fi
    '';
  };
}
