# Gateway extensions: entry symlinks into ~/.hermes/plugins and the
# enable ensure through the launcher.
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
      enabled = lib.filterAttrs (_: extension: extension.enable) config.programs.hermes.extensions;
    in
    {
      options.programs.hermes.extensions = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "linking this extension into ~/.hermes/plugins";
              package = lib.mkOption {
                type = lib.types.package;
                description = "The gateway plugin tree.";
              };
            };
          }
        );
        default = { };
        description = "Gateway extensions linked as entry symlinks into ~/.hermes/plugins/<name>.";
      };

      config = ws.whenOn "agent" {
        home.file = lib.mapAttrs' (
          name: extension: lib.nameValuePair ".hermes/plugins/${name}" { source = extension.package; }
        ) enabled;

        home.activation.ensure-hermes-extensions = lib.mkIf (enabled != { }) (
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            launcher="$HOME/.local/opt/hermes/bin/hermes"
            if [ ! -x "$launcher" ]; then
              echo "workstation: hermes extensions ensure deferred — the launcher is absent"
            else
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: _: ''
                  if [ -d "$HOME/.hermes/plugins/${name}" ] &&
                     ! grep -qE '^[[:space:]]*-[[:space:]]*${name}[[:space:]]*$' "$HOME/.hermes/config.yaml" 2>/dev/null; then
                    "$launcher" plugins enable ${name} >/dev/null 2>&1 &&
                      echo "workstation: hermes extension ${name} enabled" ||
                      echo "workstation: hermes extension ${name} enable deferred — the launcher refused"
                  fi
                '') enabled
              )}
            fi
          ''
        );
      };
    };
}
