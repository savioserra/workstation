# The check surface on the CI system: tests/nix/checks.nix over the
# template legs and the machine's report.
{
  config,
  lib,
  self,
  ...
}:
let
  ciSystem = "x86_64-linux";
  inherit (config.workstation) legs machines;
in
{
  perSystem =
    { system, pkgs, ... }:
    {
      checks = lib.optionalAttrs (system == ciSystem) (
        import ../../tests/nix/checks.nix {
          inherit self pkgs;
          home = legs.home;
          report = config.flake.workstation.report;
          legs = {
            linux = legs.linux machines.template;
            mac = legs.mac machines.template-darwin;
            home = legs.home machines.template.system machines.template.homeModules;
          };
        }
      );
    };
}
