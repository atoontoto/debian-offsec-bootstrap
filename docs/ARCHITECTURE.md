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
provides dry-run execution, HTTPS and checksum gates, archive path/type checks,
atomic files, validated removals, temporary-directory cleanup, user transitions,
and locking. APT availability is resolved on the target system so optional packages
can disappear or move without corrupting the run.

Modules contain category policy, not package lists. This prevents documentation,
profiles, and installers from drifting into independent inventories. Project-owned
executables live below `/opt/offsec` with stable links under `/usr/local/bin`.
User-scoped pipx environments remain owned by the invoking non-root account.
Static owned paths are declared in `manifests/owned-paths.txt`; dynamic executable
links are derived from the catalog so uninstallation does not guess at ownership.
Helpers are managed links into the installed bootstrap and load a generated,
root-owned `config/installed.conf`, which preserves validated custom roots and pins.

The verified GitHub channel supports its original seven-column, single-asset rows
and a ten-column component form:

```text
tool-id<TAB>component-id<TAB>owner/repo<TAB>tag<TAB>architecture<TAB>asset-regex<TAB>checksum-url<TAB>archive-executable:installed-command mappings<TAB>strip-components<TAB>verification-arguments
```

Component rows let several pinned release archives activate as one logical tool.
Mappings such as `proxy:ligolo-proxy` preserve an archive's internal filename while
exposing a specific managed command. Asset regular expressions must be fully
anchored, exactly one official release asset must match, every archive is checked
against one unambiguous SHA-256 entry from the configured upstream checksum file,
and all components pass archive/executable validation before atomic activation.
Legacy mappings without `:` retain the archive basename as the installed command.

APT identifiers can be audited offline against Debian's official repository metadata
with `make validate-debian PACKAGES_INDEX=/path/to/Packages.xz`. The release was
validated against Trixie's official amd64 `main` index on 2026-07-26; runtime
`apt-cache` checks remain authoritative for the operator's configured mirrors.
