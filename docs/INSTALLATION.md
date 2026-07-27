# Installation

## Prerequisites

Start with Debian 13 Trixie amd64, current security updates, working HTTPS, and at
least 5 GiB free before a core install. Review `config/defaults.conf`, manifests,
and all privileged scripts. Put local overrides in ignored `config/local.conf`
with root ownership and mode `0600`; environment variables and CLI options override
defaults without command evaluation.

The installer refuses other operating systems/architectures unless
`--force-unsupported` is explicitly supplied. That switch bypasses detection only;
it does not make other systems supported.

## Examples

```console
sudo ./install.sh --profile standard --desktop xfce
sudo ./install.sh --profile core --desktop none --without-wordlists --without-bloodhound
sudo ./install.sh --profile full --categories forensics,reverse-engineering
sudo ./install.sh --dry-run --non-interactive
sudo ./install.sh --non-interactive --accept-authorized-use
```

Interactive confirmations read and write through the controlling terminal, so prompts
remain visible after logging starts and answers are not copied to logs. A fresh actual
install in `--non-interactive` mode requires `--accept-authorized-use`; a dry-run does
not persist acceptance. If no controlling terminal exists, interactive mode fails
clearly instead of reading redirected input or waiting indefinitely.

`--resume` expresses intent to continue an interrupted run; all operations are
idempotent regardless of the flag. A lock under `/run/lock` prevents concurrent
install/update/uninstall operations. Optional failures are summarized and do not
mask required foundation failures.

Disk checks resolve each configured destination to its nearest existing parent and
check every distinct backing filesystem. Missing directories are not created for the
check, and a failed or malformed `df` result is reported as unknown rather than zero.
Custom roots are recorded in the installed bootstrap configuration so all helper,
update, verification, and uninstall paths continue to use them.

## Burp Suite Community

Review the PortSwigger license and obtain an official Linux installer URL and
SHA-256. Do not use a mirror. Configure:

```bash
OFFSEC_BURP_DOWNLOAD_URL='https://portswigger.net/...official-installer...'
OFFSEC_BURP_SHA256='64-lowercase-hex-characters'
```

The code enforces an official `portswigger.net` HTTPS hostname, verifies the digest,
installs under `/opt/burpsuite-community`, and creates `burpsuite`. If either value
is missing it gives a manual fallback; it never scrapes fragile HTML.

## Packet capture and Docker

Packet capture can be performed as root. If an organization prefers limited
capture-group access, configure Debian's `wireshark-common` debconf choice manually
after reviewing the local privilege implications; the bootstrap never grants
capabilities globally. Docker is invoked with sudo unless `--allow-docker-group` is
used. Docker group members can mount the host filesystem and are effectively root.

Wireless installation requires compatible hardware. The installer does not enable
monitor mode, stop NetworkManager, alter DNS, enable forwarding, or change radio
state.

## Pivoting tools

The standard `network` category installs pinned Chisel and Ligolo-ng releases.
Chisel is one `chisel` binary with explicit `client` and `server` subcommands.
Ligolo-ng is installed from its official checksum-verified proxy and agent archives
as `ligolo-proxy` and `ligolo-agent`; the generic upstream names `proxy` and `agent`
are never added to `/usr/local/bin`.

Ligolo-ng uses a TUN-based pivoting model. The agent itself does not require
administrative privileges, while the proxy operator needs permission to create and
manage a TUN interface. Debian's ordinary kernel TUN device is sufficient; this
bootstrap does not create an interface or route, enable forwarding, grant a broad
capability, change sysctls or firewall rules, or start either role. If `/dev/net/tun`
is unavailable, fix that runtime prerequisite according to the host's own security
policy rather than weakening it during installation.

For an explicitly authorized assessment, review each tool's upstream documentation
and invoke roles yourself with scoped names and credentials, for example:

```console
sudo ligolo-proxy -selfcert
ligolo-agent -connect authorized-proxy.example:11601 -accept-fingerprint '<reviewed-fingerprint>'

chisel server --port '<approved-port>' --auth '<reviewed-user:password>'
chisel client 'https://authorized-server.example' '<approved-local-port>:authorized-service.example:<approved-service-port>'
```

These are operator actions that create network activity; installation, update,
inventory, verification, and dry-run never run them. Use both tools only on systems
you own or are explicitly authorized to assess.

## Large components

Use `--without-burp`, `--without-bloodhound`, `--without-wordlists`,
`--without-cloud`, `--without-wireless`, and `--desktop none` to reduce storage.
Ghidra, mobile GUI tools, vendor cloud CLIs, Metasploit, giant cracking data, and
fuzzdb remain manual or explicit. Intentionally vulnerable applications belong in
isolated lab networks/containers and are never installed on the host by this project.
