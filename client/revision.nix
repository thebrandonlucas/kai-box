# The commit of this repository the box is built from, ending in -dirty
# when the tree had changes, as system.configurationRevision, which the
# status report carries. kai is to record it itself; then this file goes.
{ lib, ... }:
let
  repository = if builtins.pathExists ./.git then builtins.fetchGit ./. else { };
  # A repository with no commit yet has rev 0000..., and no revision.
  revision = repository.dirtyRev or repository.rev or null;
in
{
  system.configurationRevision =
    if revision == null || lib.hasPrefix "0000000000" revision then null else revision;
}
