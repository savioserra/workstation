# The routine registry, home plane: shell routines any home module registers
# per lifecycle event, composed into one tree (`<event>/<name>`) carried at
# the home generation's root (`workstation-routines`) and baked into the
# switch driver as its outgoing tree.
# | Event | Runs | Routines of | Failure |
# | --- | --- | --- | --- |
# | teardown | after the build, before the incoming activation, per name the incoming tree lacks | the outgoing generation | stops the switch |
# | activate | after the incoming activation and its receipt | the incoming generation | reports |
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.workstation.routines;

  events = {
    teardown = "Routines run before a switch activates a generation that lacks their name: the outgoing generation's undo of the activation state its capability created. A failed teardown stops the switch before the activation.";
    activate = "Routines run after a switch's activation and receipt, on every verb (apply, sync, update, rollback): the incoming generation's. A failed routine reports and never fails the switch.";
  };

  routine =
    event: name: text:
    pkgs.writeShellScript "workstation-routine-${event}-${name}" text;

  tree = pkgs.runCommand "workstation-routines" { } (
    ''
      mkdir -p ${lib.concatMapStringsSep " " (event: "$out/${event}") (builtins.attrNames events)}
    ''
    + lib.concatMapStrings (
      event:
      lib.concatStrings (
        lib.mapAttrsToList (name: text: ''
          ln -s ${routine event name text} $out/${event}/${name}
        '') cfg.${event}
      )
    ) (builtins.attrNames events)
  );

  badNames = lib.concatMap (
    event:
    map (name: "${event}.${name}") (
      builtins.filter (name: builtins.match "[a-z][a-zA-Z0-9]*" name == null) (
        builtins.attrNames cfg.${event}
      )
    )
  ) (builtins.attrNames events);
in
{
  options.workstation = {
    routines = lib.mapAttrs (
      _: description:
      lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "${description} Keyed by a camelCase routine name; the value is the shell body.";
      }
    ) events;

    switch.routines = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "The composed routine tree: the switch driver's outgoing tree, carried at the generation's root as workstation-routines.";
    };
  };

  config = {
    assertions = [
      {
        assertion = badNames == [ ];
        message = "workstation.routines: routine names are camelCase identifiers ([a-z][a-zA-Z0-9]*): ${toString badNames}";
      }
    ];
    workstation.switch.routines = tree;
    home.extraBuilderCommands = ''
      ln -s ${tree} $out/workstation-routines
    '';
  };
}
