# Deployment artifacts

Цей каталог зарезервовано для reviewed SMTP2Graph IaC. Runtime manifests не додаються до завершення Gate B та відповідних задач roadmap.

`swarm/stack.yml` є канонічним non-production Task 5.1 Swarm manifest. Він використовує external encrypted overlay, versioned external Docker Secrets з names-only mapping, Swarm Configs для reviewed runtime files та bind mount `${SMTP2GRAPH_STORAGE_HOST_PATH}` у `/data`. Локальні checks не застосовують stack, nftables або Docker state.

`scripts/bootstrap-swarm-host.sh --check` перевіряє host prerequisites. Його `--apply` створює лише reviewed non-production overlay/label/storage/firewall boundary і не deploy-ить stack, не створює Secrets та не має production mode.

Koha-derived templates не можна копіювати сюди або використовувати як готову deployment implementation.

## Experimental configuration contract

[`config/env-contract.keys`](config/env-contract.keys) є machine-checkable списком ключів, їхніх категорій і безпечних значень для [`.env.example`](../.env.example). Контракт не є SMTP2Graph upstream schema і може змінитися після Gate B.

- `public` — безпечні development values, які не є credentials;
- `secret-reference` — лише майбутні versioned Docker Secret names, ніколи не secret values.
- `secret-value` — лише safe placeholder у `.env.example`; реальне значення існує тільки у SOPS-encrypted `env.dev.enc` або `env.prod.enc` і дешифрується reconciliation-скриптом у `/dev/shm`.

Перевірка не завантажує env-файл у shell:

```bash
./scripts/verify-env.sh --example-only
```
