---
phase: 02-hardened-application-stack
plan: 01
subsystem: infra
tags: [terraform, ssh, ufw, fail2ban, auditd, sysctl, docker, hardening, pci-dss]

# Dependency graph
requires:
  - phase: 01-terraform-foundation
    provides: Droplet, VPC, cloud firewall, block storage volume
provides:
  - SSH port 9292 in cloud firewall via Terraform variable
  - Host hardening script (SSH, UFW, fail2ban, sysctl, auditd, unattended-upgrades)
  - Docker CE installation script with daemon.json (iptables:false, log rotation)
  - PCI-DSS 10.2.x audit rules
affects: [02-02-docker-application-stack, 02-03-nginx-ssl, 03-monitoring]

# Tech tracking
tech-stack:
  added: [ufw, fail2ban, auditd, unattended-upgrades, docker-ce, docker-compose-plugin]
  patterns: [drop-in config files, idempotent shell scripts, deploy user with sudo]

key-files:
  created:
    - scripts/01-harden-host.sh
    - scripts/02-install-docker.sh
    - config/sshd-hardening.conf
    - config/sysctl-hardening.conf
    - config/jail.local
    - config/audit.rules
    - config/daemon.json
  modified:
    - infra/variables.tf
    - infra/main.tf
    - infra/terraform.tfvars.example

key-decisions:
  - "Enable net.ipv4.ip_forward=1 despite hardening -- Docker requires it for container networking even with iptables:false"
  - "Use KbdInteractiveAuthentication instead of deprecated ChallengeResponseAuthentication for OpenSSH 9.6 on Ubuntu 24.04"
  - "fail2ban sshd jail uses systemd journal backend (no logpath); odoo-login jail uses auto backend for file polling"
  - "GPG key import uses --batch --yes for idempotent re-runs of Docker install script"

patterns-established:
  - "Config files in config/ directory, deployed by scripts via CONFIG_DIR variable"
  - "Scripts validate prerequisites (root check, config file existence) before execution"
  - "Non-standard SSH port (9292) as first-line defense, configured in both cloud firewall and host sshd"

requirements-completed: [HARD-01, HARD-02, HARD-03, HARD-04, HARD-05, HARD-06, HARD-07, DOCK-01, DOCK-02, DOCK-07]

# Metrics
duration: 4min
completed: 2026-03-12
---

# Phase 2 Plan 01: Host Hardening & Docker Installation Summary

**PCI-DSS host hardening with SSH/UFW/fail2ban/auditd/sysctl plus Docker CE with iptables:false and log rotation**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-12T19:13:54Z
- **Completed:** 2026-03-12T19:18:03Z
- **Tasks:** 3
- **Files modified:** 10

## Accomplishments
- Cloud firewall SSH port updated to 9292 via Terraform variable (already in prior commit e9e0c2f)
- Host hardening script covering 7 HARD requirements: SSH key-only auth, UFW default-deny, fail2ban, sysctl kernel params, unattended upgrades, file permissions, auditd PCI-DSS rules
- Docker CE installation script with official apt repo, daemon.json (iptables:false, 10MB/3-file log rotation), and deploy user in docker group
- Fixed 3 bugs in config files for Ubuntu 24.04 / Docker compatibility

## Task Commits

Each task was committed atomically:

1. **Task 1: Update Terraform firewall for SSH port 9292** - `e9e0c2f` (feat) -- prior commit, verified correct during execution
2. **Task 2: Create host hardening script + config files** - `0fe988e` (fix) -- fixed 3 config issues for Ubuntu 24.04 compatibility
3. **Task 3: Create Docker CE installation script + daemon.json** - `1171d6d` (fix) -- made GPG key import idempotent

## Files Created/Modified
- `infra/variables.tf` - Added ssh_port variable (default: 9292)
- `infra/main.tf` - Firewall SSH rule uses var.ssh_port
- `infra/terraform.tfvars.example` - Documents ssh_port = 9292
- `scripts/01-harden-host.sh` - Main hardening script (system update, SSH, UFW, fail2ban, sysctl, upgrades, permissions, auditd)
- `scripts/02-install-docker.sh` - Docker CE + Compose v2 from official repo, daemon.json deployment
- `config/sshd-hardening.conf` - SSH drop-in: port 9292, key-only, no root, idle timeout, max 3 auth tries
- `config/sysctl-hardening.conf` - Kernel params: SYN cookies, IP forwarding (for Docker), no ICMP redirects, martian logging
- `config/jail.local` - fail2ban: SSH jail (systemd backend) + Odoo login jail (auto backend)
- `config/audit.rules` - auditd: PCI-DSS 10.2.1-10.2.7, Docker/SSH/firewall tracking, immutable config
- `config/daemon.json` - Docker: iptables:false, json-file log driver, 10MB/3-file rotation, overlay2

## Decisions Made
- Enabled net.ipv4.ip_forward=1 despite "no forwarding" in plan -- Docker container networking requires it even with iptables:false. IPv6 forwarding remains disabled.
- Replaced ChallengeResponseAuthentication with KbdInteractiveAuthentication -- the former is deprecated in OpenSSH 8.7+ and Ubuntu 24.04 ships OpenSSH 9.6.
- Removed explicit logpath from fail2ban sshd jail -- when backend=systemd, fail2ban reads from the journal directly. Ubuntu 24.04 sends auth logs to the journal, not /var/log/auth.log.
- Added backend=auto for odoo-login jail -- this jail reads a real log file, not the journal, so it needs file-polling backend.
- Added --batch --yes to gpg --dearmor in Docker install script for safe re-runs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed deprecated SSH directive for OpenSSH 9.6**
- **Found during:** Task 2 (host hardening config review)
- **Issue:** ChallengeResponseAuthentication is deprecated in OpenSSH 8.7+; Ubuntu 24.04 ships 9.6
- **Fix:** Replaced with KbdInteractiveAuthentication
- **Files modified:** config/sshd-hardening.conf
- **Verification:** Directive is correct for OpenSSH 9.x
- **Committed in:** 0fe988e

**2. [Rule 1 - Bug] Fixed IP forwarding breaking Docker networking**
- **Found during:** Task 2 (sysctl config review)
- **Issue:** net.ipv4.ip_forward=0 would prevent all Docker container networking
- **Fix:** Set net.ipv4.ip_forward=1 with comment explaining Docker dependency
- **Files modified:** config/sysctl-hardening.conf
- **Verification:** Docker requires ip_forward for bridge networking even with iptables:false
- **Committed in:** 0fe988e

**3. [Rule 1 - Bug] Fixed fail2ban sshd logpath incompatible with systemd backend**
- **Found during:** Task 2 (jail.local review)
- **Issue:** sshd jail had logpath=/var/log/auth.log but backend=systemd reads from journal
- **Fix:** Removed logpath from sshd jail; added backend=auto to odoo-login jail for file-based polling
- **Files modified:** config/jail.local
- **Verification:** fail2ban documentation confirms systemd backend ignores logpath
- **Committed in:** 0fe988e

**4. [Rule 1 - Bug] Fixed non-idempotent GPG key import in Docker install**
- **Found during:** Task 3 (Docker script review)
- **Issue:** gpg --dearmor fails on re-run if key file exists (prompts for overwrite, breaks set -e)
- **Fix:** Added --batch --yes flags
- **Files modified:** scripts/02-install-docker.sh
- **Verification:** Script can now be safely re-run
- **Committed in:** 1171d6d

---

**Total deviations:** 4 auto-fixed (4x Rule 1 bugs)
**Impact on plan:** All fixes necessary for correctness on Ubuntu 24.04 with Docker. No scope creep.

## Issues Encountered
None -- all issues were bugs in the existing config files caught during execution review.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Host hardening scripts ready for deployment: SCP to droplet and execute in order
- Docker installation script ready for post-hardening execution
- Execution order documented in plan: terraform apply -> SCP files -> run 01-harden-host.sh -> run 02-install-docker.sh
- Plans 02-02 (Docker application stack) and 02-03 (Nginx/SSL) depend on this plan's completion

## Self-Check: PASSED

- All 10 claimed files exist on disk
- All 3 claimed commits (e9e0c2f, 0fe988e, 1171d6d) found in git log

---
*Phase: 02-hardened-application-stack*
*Completed: 2026-03-12*
