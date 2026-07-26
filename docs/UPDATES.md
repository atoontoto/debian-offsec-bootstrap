# Updates

The default `stable` channel honors manifest pins. `latest` may be selected in
configuration for channels explicitly permitting it, but it increases regression
risk. The weekly workflow is:

```console
sudo ./update.sh
sudo ./verify.sh
```

APT performs `update` followed by a configurable safe `upgrade --with-new-pkgs`.
It does not run a distribution release upgrade. pipx environments are reinstalled at
their manifest pins as the invoking user. Go and Cargo tools are rebuilt at their pins
through controlled staging. Managed wordlist repositories fetch exact commit IDs and
refuse local changes. Verified GitHub assets require a pinned tag and checksum source.
Digest-pinned Docker images are pulled without restarting running containers.

Use `--check`, `--apt-only`, `--tools-only`, `--category`, `--dry-run`, or
`--non-interactive`. A summary separates success, optional failure, required failure,
skips/holds, reboot markers, and `needrestart` information.

The units in `systemd/` are disabled by default. To opt in, copy both files to
`/etc/systemd/system`, review them, run `systemctl daemon-reload`, and enable only
the timer. The timer never performs major Debian upgrades and Docker stacks are not
restarted automatically.

BloodHound upgrades are explicit: `offsec-bloodhound upgrade` pulls pinned image
updates, after which the operator chooses when to recreate/start the stack. Back up
engagement-relevant data first.
