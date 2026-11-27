# The hermes pin: upstream rev and tree, the interpreter floor from the
# pinned pm/lock.json, the pin manifest, the checkout ensure.
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

      pinJson = builtins.toJSON {
        engine = {
          url = if hermes.pin != null then hermes.pin.url else "";
          rev = if hermes.pin != null then hermes.pin.rev else "";
        };
        python = pkgs.python314.version;
      };
    in
    {
      options.programs.hermes.pin = lib.mkOption {
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

      config = ws.whenOn "agent" {
        assertions = [
          {
            assertion = hermes.pin != null;
            message =
              "programs.hermes.pin is unset — keep the module default "
              + "(hermesRev in modules/agent/hermes-pin.nix) or set url, rev "
              + "and tree";
          }
        ];

        home.file = {
          ".local/opt/hermes/python".source = hermesPython;
          ".local/opt/hermes/pin.json".text = pinJson;
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
            dirty=$("$git_" -C "$checkout" status --porcelain 2>/dev/null | head -n 1 || true)
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
      };
    };
}
