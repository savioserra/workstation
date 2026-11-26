# The machine files (the flake's machine-files input: hosts/template in the
# tree, hosts/local on a machine): machine.json, identity plus `settings`, a
# home-manager option tree.
# - identity: host, user, home, system
# - keys: homeKey (linux), systemKey (the host on linux, user@host on darwin)
# - homeModules: the settings tree, the home identity, workstation.machine
{
  lib,
  root,
  overrides ? { },
}:
let
  file = root + "/machine.json";
  m = lib.importJSON file // overrides;
  need =
    name:
    m.${name}
      or (throw "workstation: ${toString file} carries no \"${name}\" — run `workstation init` (identity keys: host, user, home, system)");
  host = need "host";
  user = need "user";
  home = need "home";
  system = need "system";
  settings = m.settings or { };
  isDarwin = lib.hasSuffix "-darwin" system;
  key = "${user}@${host}";
  homeKey = if isDarwin then null else key;
  systemKey = if isDarwin then key else host;
in
{
  inherit
    host
    user
    home
    system
    settings
    isDarwin
    homeKey
    systemKey
    ;

  homeModules = [
    {
      _file = toString file;
      config = settings;
    }
    {
      _file = toString file;
      home.username = user;
      home.homeDirectory = home;
      workstation.switch = {
        homeAttr = homeKey;
        systemAttr = systemKey;
      };
      workstation.machine = {
        inherit host;
        checkout = m.checkout or null;
        vault = m.vault or null;
      };
    }
  ];
}
