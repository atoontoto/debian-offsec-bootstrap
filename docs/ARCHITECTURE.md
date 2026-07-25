# Architecture

`manifests/tool-catalog.tsv` is the source of truth for discovery, profile/category
selection, verification, inventory, and generated documentation. Channel manifests
hold installation-specific pins that do not belong in the descriptive catalog.

```text
install/update/verify/uninstall
            |
   secure shared libraries
            |
 catalog selection -> category modules -> APT / pipx / Go / Cargo / verified release
                                      -> Docker / controlled Git / documented manual
            |
    /opt/offsec + inventory + logs
```

The entry points parse fixed CLI cases and never evaluate user text. `common.sh`
provides dry-run execution, HTTPS and checksum gates, archive traversal checks,
atomic files, validated removals, temporary-directory cleanup, user transitions,
and locking. APT availability is resolved on the target system so optional packages
can disappear or move without corrupting the run.

Modules contain category policy, not package lists. This prevents documentation,
profiles, and installers from drifting into independent inventories. Project-owned
executables live below `/opt/offsec` with stable links under `/usr/local/bin`.
User-scoped pipx environments remain owned by the invoking non-root account.
Static owned paths are declared in `manifests/owned-paths.txt`; dynamic executable
links are derived from the catalog so uninstallation does not guess at ownership.

APT identifiers can be audited offline against Debian's official repository metadata
with `make validate-debian PACKAGES_INDEX=/path/to/Packages.xz`. The release was
validated against Trixie's official amd64 `main` index on 2026-07-25; runtime
`apt-cache` checks remain authoritative for the operator's configured mirrors.
