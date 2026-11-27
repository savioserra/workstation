# The lock's formatter: `nix fmt` formats the tree with the nixfmt the
# lock carries — the same binary the format gate runs.
{
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixfmt;
    };
}
