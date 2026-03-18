---
phase: 03-backup-recovery-and-documentation
plan: 01
subsystem: infra
tags: [backup, pg_dump, rclone, msmtp, cron, restore, docker, postgresql]

# Dependency graph
requires:
  - phase: 02-hardened-application-stack
    provides: Docker stack with PostgreSQL + Odoo on Block Storage, deploy scripts, .env credential pattern
provides:
  - Daily pg_dump + filestore backup script with retention and monitoring hooks
  - Offsite sync to DO Spaces Cold Storage via rclone
  - Restore/verification script with temp container isolation and four operational modes
  - Setup script for backup infrastructure deployment
  - Config templates for rclone, msmtp, and cron
affects: [03-02 documentation, 04 deployment verification, 05 monitoring]

# Tech tracking
tech-stack:
  added: [rclone, msmtp, msmtp-mta, mailutils]
  patterns: [cron-based backup scheduling, rclone S3 offsite copy, temp container restore verification, Nagios-convention status files]

key-files:
  created:
    - scripts/05-setup-backups.sh
    - scripts/06-backup-daily.sh
    - scripts/07-sync-offsite.sh
    - scripts/08-restore-backup.sh
    - config/rclone.conf.example
    - config/msmtprc.example
    - config/backup-cron
  modified:
    - config/.env.example

key-decisions:
  - "Status file uses Nagios convention (0=OK, 2=CRITICAL) for Phase 5 Icinga2 integration"
  - "Offsite sync writes separate sync-status.json alongside backup-status.json"
  - "Restore script defaults to verify-only mode (requires explicit --production for live restore)"
  - "rclone.conf.example uses SPACES_REGION_PLACEHOLDER for endpoint to support non-nyc3 regions"
  - "Retention cleanup runs BEFORE new backup to free space first"

patterns-established:
  - "Backup scripts use same grep+cut .env reading and awk substitution as Phase 2 deploy scripts"
  - "Temp file pattern: write to .filename.tmp, rename on success (prevents corrupt partial files)"
  - "Error trap writes JSON status file + sends email + cleans up temp files"
  - "Cron entries in /etc/cron.d/ with explicit user (root) and log redirect"

requirements-completed: [BACK-01, BACK-02, BACK-03, BACK-04]

# Metrics
duration: 5min
completed: 2026-03-17
---

# Phase 3 Plan 01: Backup Infrastructure Summary

**Automated daily pg_dump + filestore backup with rclone offsite to DO Spaces Cold Storage, tested restore with temp container verification, and setup script deploying rclone/msmtp/cron**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-17T22:05:00Z
- **Completed:** 2026-03-17T22:10:24Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments
- Daily backup script handles full lifecycle: pre-flight checks, pg_dump custom format, filestore tar, Sunday weekly promotion via hard link, retention cleanup (7d/28d), JSON status file, and email-on-failure
- Offsite sync copies today's backups to DO Spaces Cold Storage organized by year/month using rclone copy (not sync, preserving older remote backups)
- Restore script supports four modes: verify-only (temp PG container with 9 verification checks), production restore, local file, and remote Spaces fetch
- Setup script installs rclone + msmtp, deploys configs with awk-based credential substitution, installs cron entries, and tests connectivity

## Task Commits

Each task was committed atomically:

1. **Task 1: Create daily backup and offsite sync scripts** - `02a0ede` (feat)
2. **Task 2: Create restore and verification script** - `c57b64b` (feat)
3. **Task 3: Create config templates, setup script, and update .env.example** - `2eb1d64` (feat)

## Files Created/Modified
- `scripts/05-setup-backups.sh` - Installs rclone + msmtp, deploys configs, sets up cron, tests connectivity
- `scripts/06-backup-daily.sh` - Daily pg_dump + filestore tar + weekly promotion + retention + status + email
- `scripts/07-sync-offsite.sh` - rclone copy to DO Spaces Cold Storage by year/month
- `scripts/08-restore-backup.sh` - Restore + verification with 4 modes and temp container isolation
- `config/rclone.conf.example` - DO Spaces S3 config template with credential placeholders
- `config/msmtprc.example` - SMTP relay config template for failure notifications
- `config/backup-cron` - Cron entries: daily backup at 2:30 AM, offsite sync at 3:30 AM
- `config/.env.example` - Updated with Spaces and SMTP credential sections

## Decisions Made
- Status file uses Nagios convention (0=OK, 2=CRITICAL) for seamless Phase 5 Icinga2 integration
- Offsite sync writes separate sync-status.json to independently track sync health
- Restore defaults to verify-only mode -- explicit --production flag required for live restore (safety)
- rclone config template uses region placeholder in endpoint URL to support non-nyc3 deployments
- Retention cleanup runs before backup creation to maximize free space
- Disk space pre-flight check requires 2GB free on Block Storage before proceeding

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required. Backup credentials (Spaces keys, SMTP) are documented in `.env.example` and will be populated during deployment.

## Next Phase Readiness
- All BACK-01 through BACK-04 requirements are covered by scripts and configs
- Scripts follow execution order: run 05-setup-backups.sh after 04-setup-nginx.sh
- Documentation plan (03-02) can reference these scripts for operational procedures
- Phase 4 deployment verification can test backup/restore cycle on the live droplet
- Phase 5 Icinga2 can read backup-status.json and sync-status.json for monitoring

## Self-Check: PASSED

All 8 created files verified on disk. All 3 task commits verified in git log. All 4 scripts meet minimum line count requirements.

---
*Phase: 03-backup-recovery-and-documentation*
*Completed: 2026-03-17*
