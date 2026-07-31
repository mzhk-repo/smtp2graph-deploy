# Tests

Тестові каталоги створюються разом із першими реальними test cases відповідної roadmap-задачі. Fixtures не повинні містити production secrets, реальні MIME bodies або sensitive headers.

Єдина локальна точка входу для поточних статичних перевірок:

```bash
make validate
```

Локальний Task 3.3 MVP harness виконує patched gateway проти isolated mock Graph без Microsoft 365:

```bash
make test-local
```

Він створює лише temporary Docker resources і synthetic test material; production credentials, fixtures з PII та deployment state не використовуються.

Task 5.1 static Swarm/IaC checks не вимагають доступу до Docker daemon:

```bash
./tests/security/test-swarm-stack.sh
./tests/security/test-bootstrap-swarm-host.sh
```

Shell regression suite, зокрема Task 5.2 fake-Docker orchestration checks:

```bash
./tests/shell/run.sh
```
