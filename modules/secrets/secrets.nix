# The secrets domain: the 1Password CLI and the operator's op env fragment.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
  envFile = config.workstation.secrets.envFile;
  vault = config.workstation.secrets.vault;
in
ws.capability [ "secrets" ] {
  description = "the 1Password CLI and its env fragment";
  default = true;
  options = {
    envFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/workstation/secrets.env";
      description = "Root-only env file sourced in login shells when present (service-account tokens for headless hosts).";
    };
    vault = lib.mkOption {
      type = lib.types.str;
      default = "Workstation";
      description = "1Password vault named in secret references (op://<vault>/<item>/<field>); exported as WORKSTATION_VAULT.";
    };
  };
  config = {
    home.sessionVariables.WORKSTATION_VAULT = vault;
    home.sessionVariablesExtra = ''
      [ -r ${envFile} ] && { set -a; . ${envFile}; set +a; }
    '';
    home.packages = [ pkgs._1password-cli ];
  };
}
