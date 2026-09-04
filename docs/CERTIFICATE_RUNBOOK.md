# Ініціалізація та ротація сертифікатів

## STARTTLS ACME lifecycle

STARTTLS `fullchain.pem` і `privkey.pem` не зберігаються в SOPS. Cloudflare
DNS-01 token залишається в `env.*.enc`; root systemd timer
`smtp2graph-tls-renew.timer` дешифрує contract лише в `/dev/shm`, оновлює
Certbot lineage, versioned Docker Secrets і тільки TLS mounts gateway. Реальні
host paths передаються через `/etc/smtp2graph/tls-renewal.env`, створений
bootstrap, а не через hardcode у unit.

Перед увімкненням timer оператор одноразово запускає
`renew-tls-certificate.sh --env-file ... --prepare-only --apply`, виконує
звичайний deploy і перевіряє STARTTLS. Для diagnosis доступні `--check` та
`--dry-run`; `--force-renewal` дозволений лише в development. При невдалому
cutover job виконує service rollback і залишає попередні Docker Secrets.

Видаліть legacy `TLS_CERTIFICATE_PEM` і `TLS_PRIVATE_KEY_PEM` з кожного
`env.*.enc` через SOPS після першого успішного cutover. Нижче описаний старий
ручний TLS handoff більше не застосовується.

`scripts/deploy-orchestrator-swarm.sh --deploy --apply` перевіряє наявність
інструментів для роботи із сертифікатами на хості перед узгодженням секретів
(Secret). На хостах Ubuntu використовуються APT-пакети не старіші за
`CERTBOT_MIN_VERSION` та `CERTBOT_DNS_CLOUDFLARE_MIN_VERSION`; новіші версії
пакетів Debian також допускаються. Відсутні або застарілі пакети встановлюються
лише під час явного запуску з прапорцем `--apply`.

## Перший випуск сертифікатів

Якщо у вибраному SOPS-середовищі TLS- або Graph-сертифікати містять
значення-заповнювачі, процес розгортання запускає
`scripts/prepare-certificate-env.sh` і зупиняється **до** будь-яких змін у
Docker Secret, Swarm, сховищі або файрволі. Скрипт використовує Certbot із
DNS-01 та зашифрований токен Cloudflare для видачі TLS-сертифіката на
`SMTP_TLS_FQDN`. Окрім цього, він створює Graph X.509-сертифікат (RSA-3072)
строком дії 730 днів (2 роки).

Згенерований публічний Graph-сертифікат зберігається у файлі
`${TLS_OUTPUT_DIR}/graph-client-certificate.pem`. Завантажте його до облікових
даних сертифікатів відповідного застосунку Entra та звірте SHA-1 відбиток.

Файл `.env.certificates` (з правами `0600`, додано до `.gitignore`) містить
екрановані значення у форматі Dotenv. Скопіюйте всі його рядки у відповідний
`env.dev.enc` або `env.prod.enc` через SOPS — зокрема
`GRAPH_CERTIFICATE_THUMBPRINT` і три PEM-значення. **Не передавайте** PEM-значення
як аргументи командного рядка, не комітьте їх і не виводьте у логи чи звіти.
Після успішного перенесення до SOPS видаліть `.env.certificates` і повторно
запустіть звичайне розгортання.

## Ротація

Починайте ротацію Graph-сертифіката **не пізніше ніж за 30 днів** до закінчення
терміну дії. Порядок дій:

1. Згенеруйте новий сертифікат: 
`./scripts/prepare-certificate-env.sh \
  --env-file /opt/smtp2graph-deploy/env.dev.enc \
  --rotate-tls --apply`.
2. Завантажте новий публічний PEM до Entra та звірте відбиток.
3. Скопіюйте підготовлений ключ Graph і відбиток у SOPS.
4. Видаліть проміжний файл і повторно розгорніть.
5. Попередній сертифікат в Entra та Docker Secret зберігайте, доки smoke-тестування не пройде успішно.

TLS renewal виконується автоматично timer-ом; ручний PEM handoff до SOPS не
використовується.

## Відновлення та відкат

Якщо проміжний файл уже існує, звичайна ініціалізація повторно використає його
і не створюватиме ще один ключ. Завершіть перенесення до SOPS або безпечно
видаліть проміжний файл, перш ніж запитувати явну ротацію. Відкат виконується
виключно через відновлення перевіреного попереднього SOPS-контракту та
декларативне повторне розгортання після стандартної перевірки сумісності черги.
