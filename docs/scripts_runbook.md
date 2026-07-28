# Script runbook

## `entrypoint.sh`

- Category: 1b (deploy-adjacent runtime configuration rendering).
- Inputs: an existing tmpfs `RUNTIME_CONFIG_DIR`, mounted Docker Secret files in `DOCKER_SECRETS_DIR`, the reviewed `deploy/config/gateway-config.yml.template`, and optionally `RUNTIME_CONFIG_FILE` containing only the allowlisted non-secret keys.
- Side effects: atomically writes `config.yml` with mode `0600` only inside `RUNTIME_CONFIG_DIR`; in `run` mode it starts the gateway through its image-provided `startup.sh`.
- Safety: does not source input files; rejects unknown keys, missing/non-regular secrets, group/other-writable secrets and a runtime directory outside tmpfs. It does not log secret values.
- Check: `bash -n scripts/entrypoint.sh`, `shellcheck scripts/entrypoint.sh`, `./tests/shell/test-entrypoint.sh`.
- Rollback: restore the prior reviewed wrapper and template together; do not reuse rendered config outside its tmpfs mount.

## `upgrade-smtp2graph-fork.sh`

- Category: 2 (manual maintenance with Git ref/worktree side effects).
- Inputs: explicit build repo, upstream tag or `--latest`, reviewed patch bundle, optional ignored M365 env file.
- Side effects: fetches upstream tags, creates local `upgrade/vX.Y.Z` branch and a temporary worktree. It never pushes, deploys, deletes existing branches or resolves conflicts.
- Check: `--check` validates release selection without creating a branch.
- Rollback: remove only the explicitly reviewed local `upgrade/vX.Y.Z` branch after confirming it is not checked out; upstream v1.1.5 is not a production rollback target.
