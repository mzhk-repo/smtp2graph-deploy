PYTHON ?= python3
VENV_DIR ?= .venv
PRE_COMMIT ?= $(VENV_DIR)/bin/pre-commit

export PRE_COMMIT_HOME := $(CURDIR)/.cache/pre-commit

.PHONY: bootstrap validate verify-env test-local test-failure-local

bootstrap:
	$(PYTHON) -m venv "$(VENV_DIR)"
	"$(VENV_DIR)/bin/python" -m pip install --disable-pip-version-check --requirement requirements-dev.txt
	"$(PRE_COMMIT)" install-hooks

validate:
	$(MAKE) verify-env
	PRE_COMMIT_BIN="$(CURDIR)/$(PRE_COMMIT)" ./scripts/validate.sh

verify-env:
	./scripts/verify-env.sh --example-only

test-local:
	./tests/smoke/run.sh

test-failure-local:
	./tests/acceptance/failure/run.sh --environment staging
