# The languages domain: the members are the granularity.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../nix/lib/capability.nix { inherit config lib pkgs; };
in
ws.capability [ "languages" ] {
  description = "the language toolchains";
  default = true;
}
