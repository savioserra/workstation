# The flake's check surface: leg eval gates, the e2e persona homes and
# driver, the staged container lane. The hosts live in flake.nix; nothing
# here declares machine state.
{
  self,
  nixpkgs,
  home,
  ciSystem,
  legs,
  report,
}:
let
  pkgs = nixpkgs.legacyPackages.${ciSystem};

  e2eHome =
    selections:
    (home ciSystem [
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

  switch-routines-compose =
    pkgs.runCommand "workstation-check-switch-routines"
      {
        driver = "${e2eHome ./e2e-selections.nix}/home-path/bin/workstation-switch";
      }
      ''
        grep -q 'ws-routine-after-apply-tmux-server-skew' "$driver" \
          || { echo 'the tmux routine did not compose into the staged switch driver' >&2; exit 1; }
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
