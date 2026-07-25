# Troubleshooting

## A package is unavailable

The final report records it and continues when optional. Confirm Trixie `main` is
enabled, run `apt-cache policy PACKAGE`, and check the package's Debian tracker.
Do not solve this by adding Kali, Ubuntu, testing, or unstable repositories.

## A pipx/Go/Cargo tool fails

Run `./verify.sh --category CATEGORY`, inspect the channel manifest pin, and check
the upstream release notes. pipx runs as `SUDO_USER`; ensure that account still
exists and its home is writable. Build failures do not justify `sudo pip` or writing
into root's home.

## BloodHound does not become healthy

Run `offsec-bloodhound status` and `offsec-bloodhound logs`. Confirm Docker has at
least 8 GiB RAM available, port 8080 is free on localhost, and `.env` is mode 0600.
Do not publish database or web ports to work around a local connectivity issue.

## Burp is skipped

This is expected when an official URL and SHA-256 are not configured. Review the
PortSwigger license/download page and use the documented `config/local.conf` values.
Never substitute an unofficial mirror or disable digest verification.

## Capture permissions

Run capture tools with appropriate explicit privilege, or deliberately configure
Debian's limited Wireshark capture group after local review. The project will not
silently grant capabilities or change group membership.

## Interrupted run or low disk

Free disk space, then rerun with `--resume`; operations are idempotent. A stale
process—not a stale file—holds the `flock`, so a crash does not require deleting the
lock file. Use `--dry-run` to review the next attempt.
