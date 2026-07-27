SHELL := /bin/bash
.PHONY: lint test validate validate-debian catalog install verify

lint:
	./tests/shellcheck.sh

test:
	./tests/unit.sh
	bash ./tests/github-tools.sh
	bash ./tests/disk-space.sh
	python3 ./tests/archive-safety.py
	python3 ./tests/shell-integration.py
	python3 ./tests/prompt-pty.py || test $$? -eq 77
	bash ./tests/dry-run.sh
	./tests/idempotency.sh
	./tests/smoke-test.sh

validate:
	./tests/manifest-validation.sh
	python3 ./tests/repository-consistency.py
	./tests/compose-validation.sh
	python3 ./scripts/generate-catalog.py --check

validate-debian:
	test -n "$(PACKAGES_INDEX)" || (echo 'Set PACKAGES_INDEX to Trixie amd64 Packages.xz' >&2; exit 2)
	python3 ./tests/debian-package-index.py "$(PACKAGES_INDEX)"

catalog:
	python3 ./scripts/generate-catalog.py

install:
	sudo ./install.sh

verify:
	./verify.sh
