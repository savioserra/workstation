# The nunchux member (linux): the pinned checkout with its .platform marker
# and the launcher config rendered from the settings and entries options.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../../nix/lib/capability.nix { inherit config lib pkgs; };
  cfg = config.workstation.terminal.nunchux;
  slots = config.workstation.theme.lib.slots;

  nunchuxTree =
    ws.overlayTree
      (pkgs.fetchFromGitHub {
        owner = "datamadsen";
        repo = "nunchux";
        rev = "1546eaa980d834c331496ea9d51942be07ea9fdd";
        hash = "sha256-C7sXigf8qB5umoZSU8nsqj6vPdd8NMhmTg8B64rysUw=";
      })
      [
        {
          path = "bin/.platform";
          source = ./files/.tmux/plugins/nunchux/bin/.platform;
        }
      ];

  fieldsOf =
    e:
    removeAttrs e [
      "_module"
      "rank"
    ];
  section =
    header: fields:
    "[${header}]\n" + lib.concatStrings (lib.mapAttrsToList (k: v: "${k} = ${v}\n") fields) + "\n";

  headers = builtins.attrNames cfg.entries;
  menus = builtins.filter (lib.hasPrefix "menu:") headers;
  apps = builtins.filter (lib.hasPrefix "app:") headers;
  itemOf = h: lib.last (lib.splitString ":" h);
  topLevel = builtins.filter (h: !(lib.hasInfix "/" (itemOf h))) (menus ++ apps);
  ordered = lib.sort (
    a: b:
    let
      ra = cfg.entries.${a}.rank;
      rb = cfg.entries.${b}.rank;
    in
    if ra == rb then itemOf a < itemOf b else ra < rb
  ) topLevel;

  nunchuxConfig =
    "# Rendered from workstation.terminal.nunchux (settings, entries).\n"
    + section "settings" cfg.settings
    + lib.concatMapStrings (h: section h (fieldsOf cfg.entries.${h})) (menus ++ apps)
    + "[order]\n"
    + lib.concatMapStrings (h: itemOf h + "\n") ordered;
in
ws.capability [ "terminal" "nunchux" ] {
  description = "the nunchux launcher (linux)";
  default = pkgs.stdenv.hostPlatform.isLinux;
  enable.defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
  options = {
    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "The launcher's [settings] keys.";
    };
    entries = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.str;
          options.rank = lib.mkOption {
            type = lib.types.int;
            default = 1000;
            description = "The top-level [order] position (ties sort by name).";
          };
        }
      );
      default = { };
      description = "Launcher sections keyed by header (`app:<name>`, `app:<menu>/<name>`, `menu:<name>`); every other field renders as `key = value`. Domains contribute their own, guarded by this member's enable.";
    };
  };
  config = {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "workstation.terminal.nunchux is linux-only";
      }
    ];

    workstation.terminal.nunchux = {
      settings.fzf_colors = lib.mkDefault "fg+:${slots.text}:bold,bg+:-1,hl:cyan,hl+:cyan:bold,pointer:cyan,marker:${slots.ok},header:gray,border:gray";
      entries = {
        "menu:system" = {
          desc = "System tools";
          status = lib.removeSuffix "\n" (builtins.readFile ./files/system-status);
          rank = 10;
        };
        "app:system/btop" = {
          cmd = "btop";
          desc = "Task manager";
        };
        "app:system/journal" = {
          cmd = "journalctl -f";
          desc = "Follow system logs";
        };
      };
    };

    home.packages = [ pkgs.fzf ];
    home.file = {
      ".tmux/plugins/nunchux".source = nunchuxTree;
      ".config/nunchux/config".text = nunchuxConfig;
    };
  };
}
