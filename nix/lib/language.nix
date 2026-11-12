# Language member wrapper: the enable gate, the mise tool pins and the
# editor profile entry — one declaration per language member.
{
  lib,
  pkgs,
  config,
}:
let
  ws = import ./capability.nix { inherit config lib pkgs; };
in
{
  # language [ "languages" "node" ] {
  #   description; default?; enable?;
  #   tools?    — mise pins, merged into workstation.languages.tools;
  #   editor?   — the workstation.editor.languages.<id> entry;
  #   options?; config? }
  language =
    path: spec:
    ws.capability path {
      inherit (spec) description;
      default = spec.default or false;
      enable = spec.enable or { };
      options = spec.options or { };
      config = lib.mkMerge [
        { workstation.languages.tools = spec.tools or { }; }
        (lib.optionalAttrs (spec ? editor) {
          workstation.editor = ws.whenOn "editor" { languages.${lib.last path} = spec.editor; };
        })
        (spec.config or { })
      ];
    };
}
