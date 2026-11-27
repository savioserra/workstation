# Payload helpers, free of the module system: scripts.
{ lib, pkgs }:
{
  # script: a payload file as a program on PATH; the payload sets its own
  # shell options
  script =
    {
      name,
      file,
      inputs ? [ ],
      prelude ? "",
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = inputs;
      bashOptions = [ ];
      text = prelude + builtins.readFile file;
    };
}
