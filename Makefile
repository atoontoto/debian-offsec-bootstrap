SHELL := /bin/bash
.PHONY: lint test validate validate-debian catalog install verify

lint:
	./tests/shellcheck.sh

test:
	./tests/unit.sh
	./tests/idempotency.sh
	./tests/smoke-test.sh

validate:
	./tests/manifest-validation.sh
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
