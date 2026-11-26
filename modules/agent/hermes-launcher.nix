# The hermes launcher: the derivation and its PATH links.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
  hermes = config.programs.hermes;

  launcher = pkgs.runCommand "ws-hermes-launcher" { } ''
    install -Dm755 ${./files/hermes-launcher.sh} "$out/hermes-launcher"
    install -Dm755 ${./files/hermes-pane-resume.sh} "$out/hermes-pane-resume"
  '';
in
{
  options.programs.hermes.package = lib.mkOption {
    type = lib.types.package;
    default = launcher;
    defaultText = lib.literalExpression "launcher";
    description = ''
      The hermes launcher derivation: resolves the pinned interpreter and
      the pinned checkout from $HOME at run time, fails closed when
      either is missing. Deployed at .local/opt/hermes/bin/hermes and on
      PATH as .local/bin/hermes.
    '';
  };

  config = ws.whenOn "agent" {
    home.file = {
      ".local/opt/hermes/bin/hermes".source = "${hermes.package}/hermes-launcher";
      ".local/bin/hermes".source = "${hermes.package}/hermes-launcher";
    };
  };
}
