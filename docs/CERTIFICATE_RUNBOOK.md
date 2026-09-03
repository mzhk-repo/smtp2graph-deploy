# Bootstrap та ротація сертифікатів

`scripts/deploy-orchestrator-swarm.sh --deploy --apply` перевіряє інструменти
сертифікатів хоста перед узгодженням Secret. На Ubuntu‑хостах використовуються
пакети APT не старіші, ніж `CERTBOT_MIN_VERSION` і
`CERTBOT_DNS_CLOUDFLARE_MIN_VERSION`; новіші версії Debian‑пакетів також
підтримуються.
Відсутні або застарілі пакети встановлюються лише під час явного застосування
деплою.

## Перша проблема

Якщо у вибраному середовищі SOPS є заповнювачі для TLS‑ або Graph‑сертифікатів,
деплой запускає `scripts/prepare-certificate-env.sh`, а потім зупиняється
перед зміною Docker Secret, Swarm, сховища або правил брандмауера. Скрипт
використовує Certbot DNS‑01 з зашифрованим токеном Cloudflare для видачі TLS
для `SMTP_TLS_FQDN`. Він також створює RSA‑3072 Graph X.509‑сертифікат, дійсний
на 365 днів.

Згенерований відкритий Graph‑сертифікат зберігається у
`${TLS_OUTPUT_DIR}/graph-client-certificate.pem`. Завантажте його до відповідних
облікових даних програми Entra та перевірте його SHA‑1 відбиток.

Ігнорований файл `.env.certificates` з режимом `0600` містить екрановані
значення у форматі Dotenv. Скопіюйте його повні рядки у вибране `env.dev.enc`
або `env.prod.enc` за допомогою SOPS; це включає `GRAPH_CERTIFICATE_THUMBPRINT`
разом із трьома PEM‑значеннями. Не вставляйте PEM‑значення у аргументи оболонки,
не комітьте їх і не виводьте у звіти. Після успішної передачі SOPS видаліть
`.env.certificates`, а потім запустіть звичайний деплой знову.

## Ротація

Починайте ротацію Graph‑сертифіката щонайменше за 30 днів до закінчення терміну
дії. Створіть заміну за допомогою `prepare-certificate-env.sh --rotate-graph --apply`,
завантажте новий відкритий PEM у Entra, переверіть відбиток, скопіюйте підготовлений
ключ Graph і відбиток у SOPS, видаліть стаджинг і задеплойте знову. Залиште
попередній сертифікат Entra та Docker Secret, доки не пройде smoke‑тестування.

Для TLS запустіть `prepare-certificate-env.sh --rotate-tls --apply`, скопіюйте
дві TLS‑строки у SOPS, видаліть стаджинг і задеплойте знову. Скрипт вимагає
примусового оновлення Certbot і перевіряє виданий парний хост‑ключ. Автоматичного
запису SOPS, деплою чи видалення старих секретів не відбувається.

## Відновлення та відкат

Якщо стаджинг вже існує, звичайний bootstrap повторно його використовує і не
створює новий ключ у очікуванні. Завершіть передачу SOPS або безпечно видаліть
файл стаджингу перед запитом явної ротації. Відкат виконувати лише шляхом
відновлення перевіреного попереднього SOPS‑контракту та декларативного
деплою після звичайної оцінки сумісності черги.

`scripts/deploy-orchestrator-swarm.sh --deploy --apply` verifies the host
certificate tooling before Secret reconciliation. Ubuntu hosts use APT package
versions no older than `CERTBOT_MIN_VERSION` and
`CERTBOT_DNS_CLOUDFLARE_MIN_VERSION`; newer Debian package versions are valid.
Missing or old packages are installed during explicit deploy apply only.

## First issue

When the selected SOPS env has placeholders for TLS or Graph certificate
values, deploy runs `scripts/prepare-certificate-env.sh`, then stops before
Docker Secret, Swarm, storage, or firewall mutation. The script uses Certbot
DNS-01 with the encrypted Cloudflare token to issue TLS for `SMTP_TLS_FQDN`.
It also creates an RSA-3072 Graph X.509 certificate valid for 365 days.

The generated public Graph certificate is saved as
`${TLS_OUTPUT_DIR}/graph-client-certificate.pem`. Upload it to the intended
Entra application certificate credentials and verify its SHA-1 thumbprint.

The ignored, mode-`0600` `.env.certificates` contains escaped Dotenv values.
Copy its complete lines into the selected `env.dev.enc` or `env.prod.enc` using
SOPS; this includes `GRAPH_CERTIFICATE_THUMBPRINT` in addition to the three PEM
values. Do not paste PEM values into shell arguments, commit them, or print
them into evidence. Delete `.env.certificates` after successful SOPS handoff,
then rerun the normal deploy.

## Rotation

Start Graph certificate rotation at least 30 days before expiry. Generate the
replacement with `prepare-certificate-env.sh --rotate-graph --apply`, upload
the new public PEM in Entra, verify the thumbprint, copy the staged Graph key
and thumbprint into SOPS, delete staging, and redeploy. Keep the previous Entra
certificate and Docker Secret until smoke verification succeeds.

For TLS, run `prepare-certificate-env.sh --rotate-tls --apply`, copy the two
TLS lines into SOPS, delete staging, and redeploy. The script requests a
forced Certbot renewal and validates the issued hostname/key pair. No automatic
SOPS write, deployment, or deletion of old secrets occurs.

## Recovery and rollback

If staging already exists, the normal bootstrap reuses it and does not generate
another pending key. Complete the SOPS handoff or securely remove the staging
file before requesting an explicit rotation. Roll back only by restoring a
reviewed prior SOPS contract and declaratively redeploying after the normal
queue compatibility assessment.
