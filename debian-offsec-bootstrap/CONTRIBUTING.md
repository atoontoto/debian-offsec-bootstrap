# Contributing

Open an issue before adding a large tool or installation channel. Tool additions
must be maintained, legally redistributable by reference, pinned where practical,
HTTPS-only, represented in `manifests/tool-catalog.tsv`, and accompanied by tests.

Run `make catalog lint test validate`. Never add Kali/Ubuntu repositories, secrets,
generated BloodHound credentials, assessment data, or binaries. CI is intentionally
limited to linting, manifest validation, documentation generation, and local unit
tests; it must not scan external hosts.
