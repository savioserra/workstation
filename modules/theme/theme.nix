# The theme domain: the themes (a palette per role, dark and light ship
# here), the consumer registry, the rendered theme tree and the runtime pick
# (`workstation theme`).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
  cfg = config.workstation.theme;
  home = config.home.homeDirectory;

  paletteRoles = [
    "accent"
    "ok"
    "warn"
    "err"
    "chrome"
    "text"
    "shortcut"
    "selected_bg"
    "selected_fg"
    "inactive"
    "ramp_start"
    "ramp_mid"
    "ramp_end"
    "bg"
    "muted"
  ];

  themeType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        description = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "The picker's label.";
        };
        appearance = lib.mkOption {
          type = lib.types.enum [
            "dark"
            "light"
          ];
          description = "The background family: consumers with a dark/light mode follow it.";
        };
        palette = lib.genAttrs paletteRoles (
          role:
          lib.mkOption {
            type = lib.types.strMatching "#[0-9a-fA-F]{6}";
            description = "The ${role} role as #rrggbb.";
          }
        );
      };
    }
  );

  consumerType = lib.types.submodule {
    options = {
      file = lib.mkOption {
        type = lib.types.str;
        description = "The consumer's file inside each theme dir.";
      };
      render = lib.mkOption {
        type = lib.types.functionTo lib.types.lines;
        description = "Theme to file text; the theme carries name, appearance and palette.";
      };
      reload = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Shell lines run after a pick and after every apply.";
      };
    };
  };

  themeOf = name: t: {
    inherit name;
    inherit (t) appearance palette;
  };

  themeTree = pkgs.linkFarm "workstation-themes" (
    lib.concatLists (
      lib.mapAttrsToList (
        name: t:
        [
          {
            name = "${name}/tokens.json";
            path = pkgs.writeText "workstation-theme-${name}.json" (builtins.toJSON (themeOf name t));
          }
        ]
        ++ lib.mapAttrsToList (consumer: c: {
          name = "${name}/${c.file}";
          path = pkgs.writeText "workstation-theme-${name}-${consumer}" (c.render (themeOf name t));
        }) cfg.consumers
      ) cfg.themes
    )
  );

  program = ws.script {
    name = "workstation-theme";
    inputs = [ pkgs.coreutils ];
    prelude = ''
      THEMES=${home}/.local/share/workstation/themes
      STATE=${home}/.local/state/workstation/theme
      DEFAULT=${cfg.default}
      reload_consumers() {
      ${lib.concatMapStrings (c: c.reload) (builtins.attrValues cfg.consumers)}:
      }
    '';
    file = ./files/workstation-theme.sh;
  };
in
ws.capability [ "theme" ] {
  description = "the themes, the picker and the consumer files";
  default = true;
  options = {
    themes = lib.mkOption {
      type = lib.types.attrsOf themeType;
      default = { };
      description = "The themes by name; dark and light ship with the domain, more merge in.";
    };
    default = lib.mkOption {
      type = lib.types.str;
      default = "dark";
      description = "The theme linked when no live pick exists (the first apply, or a pick the generation dropped).";
    };
    consumers = lib.mkOption {
      type = lib.types.attrsOf consumerType;
      default = { };
      description = "Theme consumers: a file rendered per theme under ~/.local/share/workstation/themes/<theme>/ and read through ~/.local/state/workstation/theme/current; contributors guard with whenOn \"theme\".";
    };
  };
  config = {
    workstation.theme.themes = lib.mapAttrsRecursive (_: lib.mkDefault) {
      dark = import ./themes/dark.nix;
      light = import ./themes/light.nix;
    };

    assertions = [
      {
        assertion = cfg.themes ? ${cfg.default};
        message = "workstation.theme.default '${cfg.default}' names no theme (${lib.concatStringsSep ", " (builtins.attrNames cfg.themes)})";
      }
    ];

    home.packages = [ program ];
    home.file.".local/share/workstation/themes".source = themeTree;
    home.activation.workstation-theme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      ${program}/bin/workstation-theme seed || true
    '';

    workstation.terminal.nunchux = ws.whenOn [ "terminal" "nunchux" ] {
      entries = {
        "menu:theme" = {
          desc = "Theme";
          status = "workstation-theme current";
          rank = 40;
        };
      }
      // lib.mapAttrs' (
        name: t:
        lib.nameValuePair "app:theme/${name}" {
          cmd = "workstation-theme set ${name}";
          desc = t.description;
        }
      ) cfg.themes;
    };
  };
}
