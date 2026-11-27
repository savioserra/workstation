# The agent domain: the hermes runtime.
# | File | Owns |
# | --- | --- |
# | hermes-pin.nix | the pin, the interpreter floor, the pin manifest, the checkout ensure |
# | hermes-launcher.nix | the launcher derivation and its PATH links |
# | hermes-skills.nix | served skills, the authored skills, the bundled-name guard |
# | hermes-toolsets.nix | cli toolsets and disabled MCP servers |
# | hermes-skin.nix | a skin per theme, the pick's skin reload |
{ wsLib, ... }:
{
  imports = [
    ./hermes-pin.nix
    ./hermes-launcher.nix
    ./hermes-skills.nix
    ./hermes-toolsets.nix
    ./hermes-skin.nix
  ];

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
      servedSkills = lib.filterAttrs (_: skill: skill.enable) hermes.skills;
      verify = pkgs.writeShellScriptBin "hermes-verify" (builtins.readFile ./verify/hermes.sh);
    in
    ws.capability [ "agent" ] {
      description = "the hermes agent runtime and its served skills";
      default = true;
      config = {
        # the consumer smoke rides the switch: every verb runs it after the
        # activation, and the served skill names come from the option tree
        workstation.routines.activate.verifyHermes = ''
          ${verify}/bin/hermes-verify ${lib.concatStringsSep " " (lib.attrNames servedSkills)}
        '';
      };
    };
}
