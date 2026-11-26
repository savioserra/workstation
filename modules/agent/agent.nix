# The agent domain: hermes (pinned checkout, launcher, interpreter, skills,
# extensions, a skin per theme following the pick) and herdr.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
  hermes = config.programs.hermes;

  # a hermes skin from one theme's color map tokens
  hermesSkin =
    t:
    let
      p = t.palette;
    in
    {
      name = "workstation-${t.name}";
      description = "The workstation ${t.name} theme";
      colors = {
        background = p.bg;
        banner_title = p.accent;
        banner_accent = p.accent;
        banner_text = p.text;
        banner_dim = p.muted;
        banner_border = p.chrome;
        ui_accent = p.accent;
        ui_tool = p.shortcut;
        ui_label = p.shortcut;
        ui_text = p.text;
        ui_border = p.chrome;
        ui_ok = p.ok;
        ui_warn = p.warn;
        ui_error = p.err;
        prompt = p.text;
        input_rule = p.chrome;
        response_border = p.accent;
        session_label = p.shortcut;
        session_border = p.chrome;
        status_bar_bg = p.bg;
        status_bar_text = p.text;
        status_bar_strong = p.accent;
        status_bar_dim = p.muted;
        status_bar_good = p.ok;
        status_bar_warn = p.warn;
        status_bar_bad = p.err;
        status_bar_critical = p.err;
        completion_menu_bg = p.bg;
        completion_menu_current_bg = p.selected_bg;
        selection_bg = p.selected_bg;
        shell_dollar = p.accent;
        voice_status_bg = p.bg;
      };
    };
  skinFiles = lib.mapAttrs' (
    name: t:
    lib.nameValuePair ".hermes/skins/workstation-${name}.yaml" {
      source = (pkgs.formats.yaml { }).generate "hermes-skin-${name}.yaml" (hermesSkin t);
    }
  ) ws.themeTokens;

  hermesRev = "8fc0374447313e276f6b9a2764bfc750190c966a";
  hermesTree = pkgs.fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    rev = hermesRev;
    hash = "sha256-XAglpTjtcXz3N8flS3+9b9Duk636wEXcQEna21E6aZQ=";
  };
  hermesPin = {
    url = "https://github.com/NousResearch/hermes-agent";
    rev = hermesRev;
    tree = hermesTree;
  };

  lockedPythonVersion =
    if hermes.pin == null then
      null
    else
      let
        lock = builtins.fromJSON (builtins.readFile (hermes.pin.tree + "/pm/lock.json"));
        locked =
          lock.packages.python.version
            or (throw "workstation-agent: the pinned hermes rev's pm/lock.json carries no packages.python entry — the interpreter floor cannot be derived");
      in
      builtins.head (lib.splitString "+" locked);

  hermesPython =
    assert
      lockedPythonVersion == null
      || lib.versionAtLeast pkgs.python314.version lockedPythonVersion
      || throw "workstation-agent: pkgs.python314 ${pkgs.python314.version} predates the release the pinned hermes rev's pm/lock.json carries (${lockedPythonVersion}) — update the nixpkgs lock, or the hermes-agent rev must move to a lock the nixpkgs set satisfies";
    pkgs.python314;

  herdrVersion = "0.9.0";
  herdrPin =
    if pkgs.stdenv.hostPlatform.isx86_64 && pkgs.stdenv.hostPlatform.isLinux then
      {
        url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-linux-x86_64";
        sha256 = "4fa1a01158dd8043da92d31b270780b0dcc10603038d9b61cac4d81ab63fb71f";
      }
    else if pkgs.stdenv.hostPlatform.isAarch64 && pkgs.stdenv.hostPlatform.isDarwin then
      {
        url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-macos-aarch64";
        sha256 = "32b53df09872628059c789a69f02a6b8e29e14ddf26711421f3463f70c1aef17";
      }
    else
      throw "workstation-agent: no herdr release asset declared for system '${pkgs.system}' (the pin knows linux x86_64 and darwin arm64)";
  herdr =
    pkgs.runCommand "herdr-${herdrVersion}"
      {
        src = pkgs.fetchurl herdrPin;
        passthru.pinVersion = herdrVersion;
      }
      ''
        install -Dm755 "$src" "$out/bin/herdr"
      '';

  launcher = pkgs.runCommand "ws-hermes-launcher" { } ''
    install -Dm755 ${./files/hermes-launcher.sh} "$out/hermes-launcher"
    install -Dm755 ${./files/hermes-pane-resume.sh} "$out/hermes-pane-resume"
  '';

  helpers = import ./packages.nix { inherit pkgs; };

  pinJson = builtins.toJSON {
    engine = {
      url = if hermes.pin != null then hermes.pin.url else "";
      rev = if hermes.pin != null then hermes.pin.rev else "";
    };
    python = pkgs.python314.version;
  };

  authoredSkills = {
    secrets = ./skills/secrets;
    workstation = ./skills/workstation;
  };

  skillEntries = lib.flatten (
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
    ) (lib.filterAttrs (_: skill: skill.enable) hermes.skills)
  );
  extensionEntries = lib.mapAttrsToList (name: extension: {
    path = ".hermes/plugins/${name}";
    source = extension.package;
  }) (lib.filterAttrs (_: extension: extension.enable) hermes.extensions);
  entries = skillEntries ++ extensionEntries;
in
{
  options.workstation =
    (ws.capability [ "agent" ] {
      description = "the hermes agent runtime and its served skills";
      default = true;
    }).options.workstation;

  options.programs.hermes = {
    skills = lib.mkOption {
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

    extensions = lib.mkOption {
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

    cliToolsets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "browser"
        "clarify"
        "code_execution"
        "computer_use"
        "connections"
        "context_engine"
        "cronjob"
        "delegation"
        "file"
        "kanban"
        "memory"
        "session_search"
        "skills"
        "terminal"
        "todo"
        "vision"
        "web"
      ];
      description = "The cli session toolsets config.yaml carries — converged by the toolsets ensure; per-session divergence goes through this option, not hand edits.";
    };

    disabledMcpServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "rea" ];
      description = "MCP servers kept disabled in config.yaml (entries the user added and the ruled surface drops).";
    };

    pin = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              description = "The hermes-agent upstream git URL (the clone surface).";
            };
            rev = lib.mkOption {
              type = lib.types.str;
              description = "The pinned hermes-agent commit.";
            };
            tree = lib.mkOption {
              type = lib.types.raw;
              description = ''
                The pinned tree as the caller's flake input value — build-time
                assertions read it; it never enters the deployed closure.
              '';
            };
          };
        }
      );
      default = hermesPin;
      defaultText = lib.literalExpression "hermesPin";
      description = ''
        The hermes-agent runtime pin (upstream URL, pinned rev, pinned
        tree), declared by this module.
      '';
    };

    package = lib.mkOption {
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

  };

  config = ws.whenOn "agent" {
    assertions = [
      {
        assertion = hermes.pin != null;
        message =
          "programs.hermes.pin is unset — the flake must surface "
          + "`hermesAgentPin` (its pinned hermes-agent input: url, rev, "
          + "tree); see outputs.hermesAgentPin in flake.nix";
      }
    ]
    ++ map (name: {
      assertion = hermes.pin.tree == null || !builtins.pathExists (hermes.pin.tree + "/skills/${name}");
      message =
        "programs.hermes.skills.${name} collides with a skill the pinned "
        + "hermes-agent bundles — skills_sync owns that name at runtime "
        + "and would fight the declared entry symlink; rename the "
        + "declared skill";
    }) (builtins.attrNames (lib.filterAttrs (_: skill: skill.enable) hermes.skills));

    programs.hermes.skills = lib.mapAttrs (_: source: {
      enable = true;
      inherit source;
    }) authoredSkills;

    home.file = lib.mkMerge [
      (
        builtins.listToAttrs (map (entry: lib.nameValuePair entry.path { source = entry.source; }) entries)
        // {
          ".local/opt/hermes/python".source = hermesPython;
          ".local/opt/hermes/pin.json".text = pinJson;
          ".local/opt/hermes/bin/hermes".source = "${hermes.package}/hermes-launcher";
          ".local/bin/hermes".source = "${hermes.package}/hermes-launcher";
          ".local/bin/herdr".source = "${herdr}/bin/herdr";
        }
      )
      (ws.whenOn "theme" skinFiles)
    ];

    # the pick's skin, set only on change (a set rewrites config.yaml)
    workstation.theme = ws.whenOn "theme" {
      consumers.hermes.reload = ''
        if [ "$(${hermes.package}/hermes-launcher config get display.skin </dev/null 2>/dev/null)" != "workstation-$THEME" ]; then
          ${hermes.package}/hermes-launcher config set display.skin "workstation-$THEME" </dev/null >/dev/null 2>&1 || true
        fi
      '';
    };

    home.activation.ensure-hermes-checkout = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      url=${lib.escapeShellArg (if hermes.pin != null then hermes.pin.url else "")}
      rev=${lib.escapeShellArg (if hermes.pin != null then hermes.pin.rev else "")}
      checkout="$HOME/.hermes/hermes-agent"
      git_=${pkgs.git}/bin/git
      if [ -z "$rev" ]; then
        echo "workstation: hermes checkout ensure deferred — programs.hermes.pin is unset (the module's assertion names the fix)"
      elif [ ! -d "$checkout/.git" ]; then
        if "$git_" clone --quiet "$url" "$checkout" && "$git_" -C "$checkout" checkout --quiet --detach "$rev"; then
          echo "workstation: hermes checkout cloned at the pinned commit $rev"
        else
          echo "workstation: hermes checkout ensure deferred — clone failed (offline or unreachable)"
        fi
      else
        head=$("$git_" -C "$checkout" rev-parse HEAD 2>/dev/null || true)
        dirty=$("$git_" -C "$checkout" status --porcelain 2>/dev/null | head -n 1)
        if [ -n "$dirty" ]; then
          echo "workstation: hermes checkout dirty — runtime state untouched"
        elif [ "$head" = "$rev" ]; then
          echo "workstation: hermes checkout already at the pinned commit"
        elif "$git_" -C "$checkout" merge-base --is-ancestor "$head" "$rev" 2>/dev/null; then
          if "$git_" -C "$checkout" fetch --quiet origin "$rev" && "$git_" -C "$checkout" checkout --quiet --detach "$rev"; then
            echo "workstation: hermes checkout fetched to the pinned commit $rev"
          else
            echo "workstation: hermes checkout ensure deferred — fetch failed (offline or unreachable)"
          fi
        else
          echo "workstation: hermes checkout runtime-advanced ($head) — untouched"
        fi
      fi
    '';

    home.activation.ensure-hermes-extensions =
      lib.mkIf (lib.any (e: e.enable) (builtins.attrValues hermes.extensions))
        (
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
                '') (lib.filterAttrs (_: extension: extension.enable) hermes.extensions)
              )}
            fi
          ''
        );

    home.activation.ensure-hermes-toolsets = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      ${helpers.workstation-hermes-toolsets}/bin/workstation-hermes-toolsets \
        "$HOME/.hermes/config.yaml" \
        "${lib.concatStringsSep "," hermes.cliToolsets}" \
        "${lib.concatStringsSep "," hermes.disabledMcpServers}"
    '';

  };
}
