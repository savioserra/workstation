# The node member: the mise-pinned node runtime and ~/.node-version.
{ wsLib, ... }:
{
  flake.modules.homeManager.languages =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      lang = wsLib.language { inherit config lib pkgs; };
      version = "24.22.2";
    in
    lang.language [ "languages" "node" ] {
      description = "the node runtime";
      tools.node = version;
      config = {
        home.file.".node-version".source = pkgs.writeText "node-version" "${version}\n";
      };
    };
}
