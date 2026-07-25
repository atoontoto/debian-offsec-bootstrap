# Security model

The bootstrap assumes its reviewed local repository and root-owned local override
file are trusted. Package repositories, language registries, release hosting,
containers, and third-party source are separate supply-chain trust boundaries.
Debian APT is preferred because Debian provides signatures, integration, and
security maintenance. Other channels are isolated and pinned where practical.

Downloads require HTTPS. Executable archives require a configured upstream digest;
missing verification becomes a reported manual step. Archives are listed before
extraction and absolute/traversal paths are rejected. There is no `eval`, remote
script pipe, global pip, destructive Git reset, Kali/Ubuntu repository, silent
Docker-group grant, or broad capability assignment.

No proxy, handler, database, container, wireless mode, or listener starts by default.
BloodHound publishes only `127.0.0.1:8080`; databases remain on the Compose network.
The project does not open firewall ports, disable AppArmor/Secure Boot, alter DNS,
enable forwarding, modify NetworkManager, weaken sudoers, or install intentionally
vulnerable applications on the host.

Secrets are generated locally with restrictive permissions and excluded from Git.
Logging helpers redact common token/password forms; scripts never print BloodHound
secrets. Inventory records command paths/versions, not credentials. Assessment data
is outside project-owned removal roots.

Residual risks include compromised upstream releases, malicious tool behavior,
language dependency changes, Docker daemon privilege, operator misuse, and false
confidence from version-only verification. Review pins and licenses, use snapshots,
separate client data, restrict egress, and test updates in a disposable VM first.
