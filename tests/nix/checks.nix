# The flake's check surface: leg eval gates, the e2e persona homes and
# driver, the staged container lane. The legs come from nix/flake/legs.nix;
# nothing here declares machine state.
{
  self,
  pkgs,
  home,
  legs,
  report,
}:
let
  e2eHome =
    selections:
    (home pkgs.stdenv.hostPlatform.system [
      ./e2e-home.nix
      selections
    ]).activationPackage;

  evalCheck =
    name: drvPath:
    pkgs.runCommand "workstation-check-${name}"
      {
        drv = builtins.unsafeDiscardStringContext drvPath;
      }
      ''
        mkdir -p "$out"
        printf '%s\n' "$drv" > "$out/drv"
      '';
in
{
  report-reads = pkgs.runCommand "workstation-check-report-reads" {
    report = builtins.toJSON report;
    passAsFile = [ "report" ];
  } ''mkdir -p "$out" && mv "$reportPath" "$out/report.json"'';

  linux-leg-eval = evalCheck "linux-leg-eval" legs.linux.config.system.build.toplevel.drvPath;
  mac-leg-eval = evalCheck "mac-leg-eval" legs.mac.config.system.build.toplevel.drvPath;
  home-legs-eval = evalCheck "home-legs-eval" legs.home.activationPackage.drvPath;

  e2e-home = e2eHome ./e2e-selections.nix;
  e2e-minus-go-home = e2eHome ./e2e-selections-minus-go.nix;
  e2e-driver = pkgs.callPackage ./e2e.nix {
    inherit self;
    harlequinVersion = pkgs.harlequin.version;
  };

  switch-driver =
    let
      # the outgoing routine tree both gate drivers carry: each routine
      # logs beside the gate's home; `broken` fails
      probe =
        name:
        pkgs.writeShellScript "workstation-check-routine-${name}" ''
          echo "ROUTINE: ${name}" >>"$HOME/../log"
        '';
      routines = pkgs.runCommand "workstation-check-switch-driver-routines" { } ''
        mkdir -p $out/teardown $out/activate
        ln -s ${probe "activate-outgoing"} $out/activate/probe
        ln -s ${probe "teardown-gone"} $out/teardown/gone
        ln -s ${probe "teardown-kept"} $out/teardown/kept
        ln -s ${pkgs.writeShellScript "workstation-check-routine-broken" "exit 1"} $out/teardown/broken
      '';
      driver =
        homeAttr:
        import ../../nix/lib/switch.nix {
          inherit (pkgs) lib;
          inherit pkgs homeAttr routines;
          systemAttr = "sys";
        };
    in
    pkgs.runCommand "workstation-check-switch-driver"
      {
        nativeBuildInputs = [
          pkgs.git
          pkgs.jq
        ];
      }
      ''
        bash ${./switch-driver.sh} \
          ${driver null}/bin/workstation-switch \
          ${driver "old@key"}/bin/workstation-switch
        mkdir -p "$out"
      '';

  hermes-pane-resume =
    pkgs.runCommand "workstation-check-hermes-pane-resume"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.procps
        ];
      }
      ''
        bash ${./hermes-pane-resume.sh} ${../../modules/agent/files/hermes-pane-resume.sh} ${pkgs.python3}/bin/python3
        mkdir -p "$out"
      '';

  container-e2e =
    pkgs.runCommand "workstation-check-container-e2e"
      {
        src = self;
        script = ./run-container.sh;
      }
      ''
        mkdir -p "$out/bin" "$out/share"
        install -m 0755 "$script" "$out/bin/run-container-e2e"
        printf '%s\n' "$src" > "$out/share/flake-src"
        sh -n "$out/bin/run-container-e2e"
      '';
}
