# The systems and the one nixpkgs instance per system (the unfree
# acceptance applied); every leg and package reads it through withSystem.
{ inputs, lib, ... }:
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = import ../lib/license.nix { inherit lib; };
      };
    };
}
