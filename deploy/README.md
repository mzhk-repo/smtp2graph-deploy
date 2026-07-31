# Deployment artifacts

Цей каталог зарезервовано для reviewed SMTP2Graph IaC. Runtime manifests не додаються до завершення Gate B та відповідних задач roadmap.

`swarm/smtp2graph.nonproduction.yml` і `network/smtp2graph.nft` є non-production Task 4.2 policy assets. Вони не застосовуються локальними checks і потребують Gate B, approved IPv4 CIDR та explicit deployment confirmation.

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
