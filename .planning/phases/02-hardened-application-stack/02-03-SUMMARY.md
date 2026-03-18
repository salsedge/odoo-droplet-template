---
phase: 02-hardened-application-stack
plan: 03
subsystem: infra
tags: [nginx, ssl, letsencrypt, certbot, reverse-proxy, hsts, tls]

# Dependency graph
requires:
  - phase: 02-hardened-application-stack
    provides: Host hardening with UFW allowing ports 80/443 (plan 02-01)
provides:
  - Nginx reverse proxy config for Odoo (HTTP/HTTPS)
  - Let's Encrypt SSL setup script with HTTP-01 challenge
  - Certbot auto-renewal via systemd timer
  - Security headers (HSTS, CSP, X-Frame-Options, X-Content-Type-Options)
  - Database manager route blocking (/web/database -> 403)
affects: [03-monitoring, 04-backup-recovery, 05-deployment-verification]

# Tech tracking
tech-stack:
  added: [nginx, certbot, letsencrypt]
  patterns: [two-stage-nginx-deploy, domain-placeholder-sed, systemd-timer-renewal]

key-files:
  created: []
  modified:
    - config/nginx/odoo-pre-ssl.conf
    - config/nginx/odoo.conf
    - scripts/04-setup-nginx.sh

key-decisions:
  - "Added DNS resolver (1.1.1.1/1.0.0.1) for OCSP stapling -- required for ssl_stapling to function"
  - "Added DNS pre-check in setup script to prevent wasted certbot rate-limited attempts"
  - "HTTP-01 challenge chosen over DNS-01 for simpler setup (no DO API token needed for certbot)"

patterns-established:
  - "Two-stage Nginx deploy: pre-SSL config for certbot challenge, then full SSL config after cert issuance"
  - "DOMAIN_PLACEHOLDER in config files replaced by sed during deployment"
  - "Certbot renewal via systemd timer (not cron) with RandomizedDelaySec for load distribution"

requirements-completed: [PROXY-01, PROXY-02, PROXY-03, PROXY-04, PROXY-05]

# Metrics
duration: 3min
completed: 2026-03-12
---

# Phase 2 Plan 03: Nginx Reverse Proxy & SSL Summary

**Nginx reverse proxy with TLS 1.2/1.3, HSTS, OCSP stapling, security headers, database route blocking, and certbot auto-renewal via systemd timer**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-12T19:14:00Z
- **Completed:** 2026-03-12T19:17:10Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Full SSL Nginx config with modern TLS, HSTS, OCSP stapling, and Odoo-compatible CSP
- Pre-SSL config for clean certbot HTTP-01 challenge workflow
- Setup script with DNS resolution pre-check and two-stage deployment
- Certbot auto-renewal via systemd timer (twice daily with 1h random delay)
- Database manager routes blocked at Nginx level (/web/database -> 403)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Nginx configuration files** - `9007613` (feat)
2. **Task 2: Create Nginx installation and certbot setup script** - `3bbe823` (feat)

## Files Created/Modified
- `config/nginx/odoo-pre-ssl.conf` - Temporary port-80 config for certbot HTTP-01 challenge
- `config/nginx/odoo.conf` - Full SSL reverse proxy config with security headers and route blocking
- `scripts/04-setup-nginx.sh` - Nginx/certbot install, SSL provisioning, and systemd timer setup

## Decisions Made
- Added DNS resolver directive (1.1.1.1/1.0.0.1) for OCSP stapling -- without it, `ssl_stapling on` silently fails
- Added DNS resolution pre-check before certbot to prevent wasted rate-limited attempts
- HTTP-01 challenge (not DNS-01) for simpler setup -- no DO API token needed for certbot

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added DNS resolver for OCSP stapling**
- **Found during:** Task 1 (Nginx configuration files)
- **Issue:** `ssl_stapling on` was configured without a `resolver` directive, causing OCSP stapling to silently fail or log errors
- **Fix:** Added `resolver 1.1.1.1 1.0.0.1 valid=300s; resolver_timeout 5s;` after stapling directives
- **Files modified:** config/nginx/odoo.conf
- **Verification:** Nginx config syntax is valid; resolver enables OCSP stapling at runtime
- **Committed in:** 9007613 (Task 1 commit)

**2. [Rule 2 - Missing Critical] Added DNS pre-check before certbot**
- **Found during:** Task 2 (Setup script)
- **Issue:** Script ran certbot without verifying DNS resolves to the server -- failed challenges waste rate-limited attempts (5 failures per hour per domain)
- **Fix:** Added `dig` + `curl ifconfig.me` check before certbot, with clear error/warning messages
- **Files modified:** scripts/04-setup-nginx.sh
- **Verification:** Script exits with error if DNS returns empty; warns if IP mismatch
- **Committed in:** 3bbe823 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical)
**Impact on plan:** Both fixes prevent runtime failures. No scope creep.

## Issues Encountered

Pre-existing uncommitted changes found in `config/odoo.conf` (02-02) and `config/sshd-hardening.conf` (02-01) from a prior editing session. These were out of scope for 02-03 and logged to `deferred-items.md`. A parallel executor for plan 02-02 was also creating commits simultaneously, but this did not affect 02-03 execution.

## User Setup Required

Before running the script:
1. DNS A record must point the domain to the droplet's public IP
2. Wait for DNS propagation (verify with `dig <domain>`)

**Execution:**
```bash
ssh -p 9292 deploy@<droplet-ip>
sudo bash /tmp/odoo-setup/scripts/04-setup-nginx.sh odoo.example.com admin@example.com
```

## Next Phase Readiness
- Nginx/SSL configuration complete and ready for deployment
- Setup script ready for execution on hardened droplet (after 02-01 and 02-02)
- Phase 3 (Backup, Recovery, and Documentation) can proceed once Phase 2 deployment is verified

## Self-Check: PASSED

All files verified present, all commit hashes confirmed in git log.

---
*Phase: 02-hardened-application-stack*
*Completed: 2026-03-12*
