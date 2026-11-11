# The nunchux member (linux): the pinned checkout with its .platform marker
# and the launcher config rendered from the settings and entries options;
# with the theme on, one config per theme, fzf colors from its palette,
# read through the pick.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../../nix/lib/capability.nix { inherit config lib pkgs; };
  cfg = config.workstation.terminal.nunchux;
  home = config.home.homeDirectory;

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
    settings:
    "# Rendered from workstation.terminal.nunchux (settings, entries).\n"
    + section "settings" settings
    + lib.concatMapStrings (h: section h (fieldsOf cfg.entries.${h})) (menus ++ apps)
    + "[order]\n"
    + lib.concatMapStrings (h: itemOf h + "\n") ordered;

  # fzf --color from the palette roles; bg left to the tmux popup canvas
  fzfColors =
    p:
    lib.concatStringsSep "," [
      "fg+:${p.text}:bold"
      "bg+:-1"
      "hl:${p.accent}"
      "hl+:${p.accent}:bold"
      "pointer:${p.accent}"
      "marker:${p.ok}"
      "header:${p.muted}"
      "border:${p.chrome}"
      "label:${p.accent}"
      "prompt:${p.accent}"
      "info:${p.muted}"
      "spinner:${p.accent}"
      "separator:${p.chrome}"
      "scrollbar:${p.chrome}"
    ];
in
ws.capability [ "terminal" "nunchux" ] {
  description = "the nunchux launcher (linux)";
  default = pkgs.stdenv.hostPlatform.isLinux;
  enable.defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
  options = {
    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "The launcher's [settings] keys; with the theme on, an unset `fzf_colors` takes the pick's palette.";
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

    workstation.theme = ws.whenOn "theme" {
      consumers.nunchux = {
        file = "nunchux.conf";
        render = t: nunchuxConfig ({ fzf_colors = fzfColors t.palette; } // cfg.settings);
      };
    };

    workstation.terminal.nunchux = {
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
      ".config/nunchux/config" =
        if config.workstation.theme.enable then
          {
            source = config.lib.file.mkOutOfStoreSymlink "${home}/.local/state/workstation/theme/current/nunchux.conf";
          }
        else
          { text = nunchuxConfig cfg.settings; };
    };
  };
}
