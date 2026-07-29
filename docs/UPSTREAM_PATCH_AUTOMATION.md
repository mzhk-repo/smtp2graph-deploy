# Автоматизація upstream patch bundle

`scripts/upgrade-smtp2graph-fork.sh` переносить reviewable patch assets на explicit або latest stable upstream tag у локальну `upgrade/vX.Y.Z` branch. Він не виконує push, PR, deploy або automatic conflict resolution.

## Bundle

`patches/smtp2graph/v1.1.5/manifest.env` визначає upstream remote, base tag, Node 20 і ordered list п'яти assets: Retry-After, permanent error → `failed`, durable enqueue before `250`, qualification tests, SMTP policy та storage guards. Git version control є єдиним integrity mechanism для manifest і patch files; CI template, Dockerfile та display-name test не входять у bundle.

## Використання

```bash
./scripts/upgrade-smtp2graph-fork.sh --release vX.Y.Z --check
./scripts/upgrade-smtp2graph-fork.sh --release vX.Y.Z --apply
./scripts/upgrade-smtp2graph-fork.sh --release vX.Y.Z --apply --test-image smtp2graph-local-test:vX-Y-Z
./scripts/upgrade-smtp2graph-fork.sh --latest --apply --env-file /safe/path/.env
```

`--apply` використовує isolated temporary worktree. Conflict, rejected hunk, checksum mismatch або regression failure зберігає його шлях для ручного review. Після успіху automation видаляє і temporary worktree, і local `upgrade/vX.Y.Z` branch; source of truth залишається у versioned control-plane assets.

SMTP2Graph v1.1.5 містить CRLF source files, тоді як reviewable patch assets
містять LF additions. Скрипт застосовує Git patches з `--ignore-space-change`;
це допускає лише line-ending/whitespace drift, але все одно fail-closed для
відсутнього або зміненого semantic hunk.

Local build, unit і receive tests обов'язкові. Без явного `--env-file` результат `PARTIAL` з exit 0; повний M365 suite запускається лише за explicit `--env-file` через `DOTENV_CONFIG_PATH`, без `source` або друку secret values.

`--test-image NAME:TAG` допустимий лише разом із `--apply`. Після успішного patch replay і local regressions automation збирає Docker image з temporary worktree та виводить його local reference. Це не GHCR push, release image або supply-chain evidence. Caller відповідає за видалення image після isolated test; worktree і local `upgrade/vX.Y.Z` branch очищуються automation як звичайно.

## Troubleshooting

- Upstream already містить fix: не пропускати empty patch; оновити bundle після applicability review.
- Existing divergent `upgrade/*` branch: не reset-ити її; порівняти patch-id вручну.
- M365 failure: не трактувати local pass як Gate B decision; зберегти лише redacted evidence.
- Conflict: переглянути preserved worktree, виправити bundle reviewed зміною, не редагувати release branch автоматично.
