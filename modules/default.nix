# The capability domains: each entry is a flake-parts module contributing
# `flake.modules.<class>.<domain>` and importing its feature and member files;
# every contribution gates itself on its own enable option.
{
  imports = [
    ./agent/agent.nix
    ./database/database.nix
    ./editor/editor.nix
    ./fonts/fonts.nix
    ./foundation/foundation.nix
    ./languages/languages.nix
    ./network/network.nix
    ./secrets/secrets.nix
    ./terminal/terminal.nix
    ./theme/theme.nix
  ];
}
