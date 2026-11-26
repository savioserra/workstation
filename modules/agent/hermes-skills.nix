# Served hermes skills: entry symlinks per profile, the authored skills,
# the guard against names the pinned hermes bundles.
{ wsLib, ... }:
{
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
      enabled = lib.filterAttrs (_: skill: skill.enable) hermes.skills;

      authoredSkills = {
        secrets = ./skills/secrets;
        workstation = ./skills/workstation;
      };

      entries = lib.flatten (
        lib.mapAttrsToList (
          name: skill:
          map (profile: {
            path =
              if profile == "default" then
                ".hermes/skills/${name}"
              else
                ".hermes/profiles/${profile}/skills/${name}";
            source = skill.source;
          }) skill.profiles
        ) enabled
      );
    in
    {
      options.programs.hermes.skills = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "serving this skill to the target profiles";
              profiles = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "default" ];
                description = "Target hermes profiles: default is ~/.hermes/skills, any other name ~/.hermes/profiles/<name>/skills.";
              };
              source = lib.mkOption {
                type = lib.types.path;
                description = "The skill tree as a store path.";
              };
            };
          }
        );
        default = { };
        description = "Skills served to hermes profiles as entry symlinks.";
      };

      config = ws.whenOn "agent" {
        assertions = map (name: {
          assertion = hermes.pin.tree == null || !builtins.pathExists (hermes.pin.tree + "/skills/${name}");
          message =
            "programs.hermes.skills.${name} collides with a skill the pinned "
            + "hermes-agent bundles — skills_sync owns that name at runtime "
            + "and would fight the declared entry symlink; rename the "
            + "declared skill";
        }) (builtins.attrNames enabled);

        programs.hermes.skills = lib.mapAttrs (_: source: {
          enable = true;
          inherit source;
        }) authoredSkills;

        home.file = builtins.listToAttrs (
          map (entry: lib.nameValuePair entry.path { source = entry.source; }) entries
        );
      };
    };
}
