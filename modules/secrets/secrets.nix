# The secrets domain: the 1Password CLI and the operator's op env fragment.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  op = pkgs._1password-cli;
in
{
  options.workstation.secrets = {
    enable = lib.mkEnableOption "the 1Password CLI and its env fragment" // {
      default = true;
    };

    envFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/workstation/secrets.env";
      description = "Root-only env file sourced in login shells when present (service-account tokens for headless hosts).";
    };
  };

  config = lib.mkIf config.workstation.secrets.enable {
    home.sessionVariablesExtra = ''
      [ -r ${config.workstation.secrets.envFile} ] && { set -a; . ${config.workstation.secrets.envFile}; set +a; }
    '';

    home.packages = [ op ];
  };
}
