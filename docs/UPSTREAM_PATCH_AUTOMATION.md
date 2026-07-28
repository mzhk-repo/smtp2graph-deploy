# Автоматизація upstream patch bundle

`scripts/upgrade-smtp2graph-fork.sh` переносить reviewable patch assets на explicit або latest stable upstream tag у локальну `upgrade/vX.Y.Z` branch. Він не виконує push, PR, deploy або automatic conflict resolution.

## Bundle

`patches/smtp2graph/v1.1.5/manifest.env` визначає annotated upstream tag object `3a1ab485…`, його peeled commit `d5280a5…`, owner, Node 20 і SHA-256 чотирьох assets: Retry-After, permanent error → `failed`, durable enqueue before `250`, qualification tests. CI template, Dockerfile та display-name test не входять у bundle.

## Використання

```bash
./scripts/upgrade-smtp2graph-fork.sh --release vX.Y.Z --check
./scripts/upgrade-smtp2graph-fork.sh --release vX.Y.Z --apply
./scripts/upgrade-smtp2graph-fork.sh --latest --apply --env-file /safe/path/.env
```

`--apply` використовує isolated temporary worktree. Conflict, rejected hunk, checksum mismatch або regression failure зберігає його шлях для ручного review. Успіх залишає лише local upgrade branch.

Local build, unit і receive tests обов'язкові. Якщо ignored M365 env file неповний, результат `PARTIAL` з exit 0; повний M365 suite запускається лише через `DOTENV_CONFIG_PATH`, без source або друку secret values.

## Troubleshooting

- Upstream already містить fix: не пропускати empty patch; оновити bundle після applicability review.
- Existing divergent `upgrade/*` branch: не reset-ити її; порівняти patch-id вручну.
- M365 failure: не трактувати local pass як Gate B decision; зберегти лише redacted evidence.
- Conflict: переглянути preserved worktree, виправити bundle reviewed зміною, не редагувати release branch автоматично.
