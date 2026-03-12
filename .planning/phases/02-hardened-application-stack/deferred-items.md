# Deferred Items - Phase 02

## Resolved

### 1. config/sshd-hardening.conf - OpenSSH 9.x directive rename
- **Issue:** `ChallengeResponseAuthentication` renamed to `KbdInteractiveAuthentication` in OpenSSH 9.x (Ubuntu 24.04)
- **Resolved in:** Plan 02-01 execution, commit 0fe988e

## Pending

### 1. config/odoo.conf - Odoo 19 parameter naming
- **Issue:** `xmlrpc_interface`/`xmlrpc_port`/`longpolling_port` renamed in Odoo 17+ to `http_interface`/`http_port`/`gevent_port`
- **Belongs to:** Plan 02-02
- **Action needed:** Include in 02-02 execution commit
