# The node member: nodejs_24 and ~/.node-version derived from it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ws = import ../../../nix/lib/capability.nix { inherit config lib pkgs; };
  nodejs = pkgs.nodejs_24;
in
ws.capability [ "languages" "node" ] {
  description = "the node runtime";
  config = {
    home.packages = [ nodejs ];
    home.file.".node-version".source = pkgs.writeText "node-version" "${nodejs.version}\n";
  };
}
