# The machine files (the flake's machine-files input: hosts/template in the
# tree, hosts/local on a machine): machine.json, identity plus `settings`, a
# home-manager option tree; peers.nix, the A2A peers.
# - identity: host, user, home, system, key
# - homeModules: the settings tree, the home identity, workstation.machine
{ lib, root }:
let
  file = root + "/machine.json";
  m = lib.importJSON file;
  need =
    name:
    m.${name}
      or (throw "workstation: ${toString file} carries no \"${name}\" — run `workstation init` (identity keys: host, user, home)");
  host = need "host";
  user = need "user";
  home = need "home";
  settings = m.settings or { };
in
{
  inherit
    host
    user
    home
    settings
    ;
  system = m.system or "x86_64-linux";
  key = "${user}@${host}";

  homeModules = [
    {
      _file = toString file;
      config = settings;
    }
    {
      _file = toString file;
      home.username = user;
      home.homeDirectory = home;
      workstation.machine = {
        inherit host;
        checkout = m.checkout or null;
        vault = m.vault or null;
        peers = import (root + "/peers.nix");
      };
    }
  ];
}
