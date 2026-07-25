# BloodHound CE stack

The stack binds its web interface to `127.0.0.1:8080` and exposes no database
ports. Images are pinned to version tags and are upgraded only by the explicit
`offsec-bloodhound upgrade` command. Installation does not start containers.

Allow at least 4 CPU cores, 8 GiB RAM, and 10 GiB free disk. Runtime secrets are
generated into `/opt/offsec/stacks/bloodhound/.env` with mode `0600`; never copy
that file into Git or a support ticket.

Use `offsec-bloodhound start|stop|status|logs|backup|upgrade`. To change the
administrator password, use the Administration UI at `http://127.0.0.1:8080/`.
Image upgrades do not restart an active stack automatically.
