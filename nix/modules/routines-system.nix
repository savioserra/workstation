# The routine registry, system plane: the operator's home routine tree
# linked at the system generation's root (`workstation-routines`), the
# switch driver's incoming tree on a system switch.
{
  config,
  lib,
  ...
}:
let
  user = config.workstation.host.user;
  users = config.home-manager.users or { };
in
{
  config = lib.mkIf (user != null && users ? ${user}) {
    system.systemBuilderCommands = ''
      ln -s ${users.${user}.workstation.switch.routines} $out/workstation-routines
    '';
  };
}
