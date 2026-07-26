# debian-offsec-bootstrap

> **AUTHORIZED USE ONLY.** Use this project only on systems you own or have
> explicit permission to assess. The operator is responsible for written scope,
> consent, evidence handling, and applicable law. Installation is not authorization.

`debian-offsec-bootstrap` is a reproducible post-installation and maintenance
system that turns a fresh **Debian 13 “Trixie” amd64** host into a curated
security-auditing workstation. It is not a distribution and does not build an ISO.
Debian remains the operating system and security boundary; this repository adds
reviewable manifests, isolated tool channels, updates, verification, and safe
uninstallation.


## Quick start

Review the scripts first, then on a fresh Debian 13 amd64 installation run:

```console
git clone https://github.com/atoontoto/debian-offsec-bootstrap.git
cd debian-offsec-bootstrap
sudo ./install.sh --profile standard --desktop xfce
sudo ./update.sh
sudo ./verify.sh --profile standard
```


## Profiles and storage

| Profile | Included catalog tools | Typical download | Typical installed size | Purpose |
|---|---:|---:|---:|---|
| core | 25 | 1–3 GiB | 3–6 GiB | Small CLI auditing baseline |
| standard | 100 | 5–12 GiB | 15–30 GiB | Curated cross-discipline workstation; default |
| full | 160 non-optional entries | 12–30 GiB | 35–80 GiB | Complete supported catalog, with many manual items |

The catalog contains 189 unique tools/resources in total, including 29 explicit
opt-ins. Actual disk use depends on desktop packages, language build caches,
containers, wordlists, symbols, and tool versions. The minimum practical host is
4 CPU cores, 8 GiB RAM, and 40 GiB free disk; 8 cores, 16–32 GiB RAM, and 100 GiB
free SSD space are recommended. BloodHound alone benefits from at least 8 GiB RAM.

Categories are `network`, `web`, `ad`, `passwords`, `exploitation`, `cloud`,
`wireless`, `reverse-engineering`, `forensics`, `osint`, and `containers`.
Choose them independently with `--categories web,network,ad`. Wireless tools,
monitor mode, large mobile/GUI tools, cloud vendor CLIs, large wordlists,
Metasploit, and Ghidra are not forced onto a host. Use `--without-wordlists`,
`--without-bloodhound`, `--without-burp`, `--without-cloud`, and desktop `none`
to reduce storage.

## Installation behavior

APT packages come from configured Debian repositories and are checked with
`apt-cache` before installation. Python CLIs use user-owned pipx environments;
Go and Cargo tools build in an unprivileged staging directory and are installed
under `/opt/offsec`; verified release support refuses a download without its
configured checksum. No global `sudo pip`, Kali repository, `curl | bash`, or
unattended source script is used.

```console
sudo ./install.sh                       # standard, no desktop
sudo ./install.sh --profile core
sudo ./install.sh --profile full
sudo ./install.sh --categories web,network,ad
sudo ./install.sh --desktop xfce        # also supports gnome, kde, none
sudo ./install.sh --with-burp --with-bloodhound --with-wordlists
sudo ./install.sh --non-interactive --accept-authorized-use --resume
sudo ./install.sh --dry-run
```

Docker access remains through `sudo`. `--allow-docker-group` is an explicit opt-in
because membership in that group is effectively root access. Wireshark capture
group configuration is also not automatic; see [Installation](docs/INSTALLATION.md).
Existing shell dotfiles are backed up before a small, removable source line is
added. Themes and wallpaper are untouched.

## Optional applications

BloodHound CE is a pinned Docker Compose stack installed under
`/opt/offsec/stacks/bloodhound`. It binds only to `127.0.0.1:8080`, generates
local secrets in a root-only ignored `.env`, and does not start automatically:

```console
offsec-bloodhound start
offsec-bloodhound status
offsec-bloodhound logs
offsec-bloodhound stop
offsec-bloodhound upgrade
```

Burp Suite Community is never redistributed. Set the official PortSwigger HTTPS
installer URL and published SHA-256 in a root-owned `config/local.conf`, review
PortSwigger's license, then use `--with-burp`. If stable unattended URL discovery
or a digest is unavailable, the installer reports a manual step instead of scraping
HTML. Launch an installed copy with `offsec-burp`.

Metasploit uses only the documented official Rapid7 path and is intentionally
manual until the operator accepts that additional package trust boundary. Its
database and handlers are never initialized or started automatically.

## Updates, verification, and removal

```console
sudo ./update.sh
sudo ./update.sh --apt-only
sudo ./update.sh --tools-only --category web
sudo ./update.sh --check
sudo ./update.sh --dry-run

./verify.sh --profile standard
./verify.sh --category web --quick
./verify.sh --json

sudo ./uninstall.sh --tool TOOL
sudo ./uninstall.sh --category CATEGORY
sudo ./uninstall.sh --all
sudo ./uninstall.sh --all --purge-data
```

Updates use Debian's safe upgrade, pinned pipx/Go/Cargo reinstalls,
commit-pinned managed Git resources, verified release downloads, and digest-pinned
Docker image pulls. Active stacks are not restarted. The optional systemd timer is shipped
disabled. Verification checks manifests, commands, pipx, Compose, symlinks,
permissions, versions, and inventory. It returns nonzero only for missing required
core-profile commands or invalid required state.

Uninstall never automatically removes shared APT packages or user assessment data.
`--purge-data` removes only validated project-owned state/resources; engagement
directories remain untouched.

## Locations and helpers

- Tools and managed resources: `/opt/offsec`
- Wordlists: `/usr/share/wordlists` and `/opt/offsec/resources`
- Inventory: `/var/lib/debian-offsec-bootstrap/inventory.json`
- Logs: `/var/log/debian-offsec-bootstrap/`
- Engagements: `~/engagements/NAME` via `offsec-project-new NAME`

Helpers include `offsec-tools`, `offsec-status`, `offsec-update`,
`offsec-wordlists`, `offsec-bloodhound`, `offsec-burp`, and
`offsec-project-new`. None of them scan or start listeners implicitly.

## Documentation

- [Installation](docs/INSTALLATION.md), [updates](docs/UPDATES.md), and
  [troubleshooting](docs/TROUBLESHOOTING.md)
- [Architecture](docs/ARCHITECTURE.md) and [security model](docs/SECURITY_MODEL.md)
- [Generated tool catalog](docs/TOOL_CATALOG.md)
- [Contributing](CONTRIBUTING.md) and [security reports](SECURITY.md)

The bootstrap source is MIT licensed. Every installed tool, image, resource, and
wordlist remains governed by its individual upstream license; inclusion in the
catalog does not relicense or redistribute it. Operators must review third-party
terms, especially proprietary/manual tools and datasets.
