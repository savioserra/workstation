# The capability helpers as the `wsLib` module argument of every flake-parts
# module: each domain file builds its `ws` from the home plane's config.
# | Helper | Call |
# | --- | --- |
# | capability | `wsLib.capability { inherit config lib pkgs; }` (enable, whenOn, themeTokens, payload) |
# | language | `wsLib.language { inherit config lib pkgs; }` (the language member wrapper) |
# | payload | `wsLib.payload { inherit lib pkgs; }` (script, overlayTree) |
{
  _module.args.wsLib = {
    capability = import ../lib/capability.nix;
    language = import ../lib/language.nix;
    payload = import ../lib/payload.nix;
  };
}
