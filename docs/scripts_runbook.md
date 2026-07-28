# Script runbook

## `upgrade-smtp2graph-fork.sh`

- Category: 2 (manual maintenance with Git ref/worktree side effects).
- Inputs: explicit build repo, upstream tag or `--latest`, reviewed patch bundle, optional ignored M365 env file.
- Side effects: fetches upstream tags, creates local `upgrade/vX.Y.Z` branch and a temporary worktree. It never pushes, deploys, deletes existing branches or resolves conflicts.
- Check: `--check` validates release selection without creating a branch.
- Rollback: remove only the explicitly reviewed local `upgrade/vX.Y.Z` branch after confirming it is not checked out; upstream v1.1.5 is not a production rollback target.
