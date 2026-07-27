# Changelog

## Unreleased

- Added first-class pinned Chisel and checksum-verified, multi-component Ligolo-ng
  support to the standard network profile, without starting networking behavior.
- Extended verified GitHub manifests with backward-compatible component rows and
  executable rename mappings, atomic activation/rollback, and per-component checks.
- Fixed controlling-terminal prompts, explicit non-interactive authorization, prompt
  logging isolation, and logging-pipeline shutdown.
- Fixed disk checks for missing/custom destinations and multiple filesystems, with
  explicit handling for `df` failures and non-truncated GiB reporting.
- Fixed strict-mode false failures, required-tool result classification, dry-run side
  effects, custom-root helpers, pinned updates, and safer idempotent uninstallation.
- Hardened archive extraction, managed directories/links, atomic bootstrap activation,
  Git resources, release assets, and Docker images; expanded regression and consistency
  validation.

## 1.0.0 - 2026-07-25

- Initial Debian 13 amd64 bootstrap with core, standard, and full profiles.
- Added APT, pipx, Go, Cargo, verified-release, Docker, manual, update, inventory,
  verification, uninstall, desktop, wordlist, tests, and documentation systems.
