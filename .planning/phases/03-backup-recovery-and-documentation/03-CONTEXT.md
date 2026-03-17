# Phase 3: Backup, Recovery, and Documentation - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Automated PostgreSQL + Odoo filestore backup with offsite sync to DO Spaces, tested restore procedures with verification, and comprehensive deployment/operational documentation. Covers BACK-01 through BACK-04 and DOC-01 through DOC-04. Monitoring integration (alerting on backup failures via Icinga2) is Phase 5 — this phase prepares status files for that.

</domain>

<decisions>
## Implementation Decisions

### Backup scheduling & scope
- Backup includes both PostgreSQL (pg_dump) and Odoo filestore (tar) — NOT deployment configs (those are in git)
- Daily backup runs early morning (2-4 AM) via system cron
- Standalone bash script in scripts/ directory, triggered by cron — consistent with Phase 2 script pattern
- On failure: log to file, send email notification (requires SMTP config), AND write exit code/status files for Phase 5 Icinga2 checks — all three failure reporting mechanisms

### Restore workflow
- Both automated restore script AND documented manual steps in operational procedures
- Restore verification uses a temporary isolated PG container — production stays untouched during verification
- Thorough verification: DB connects, expected tables exist, key table row counts match, temp Odoo instance boots against restored DB
- Script supports both local backup files AND remote fetch from DO Spaces via rclone (--from-spaces flag)

### Retention & offsite sync
- Weekly backups are Sunday's daily backup promoted/tagged as weekly — no separate weekly cron job
- DO Spaces bucket organized by year/month directories: 2026/03/odoo-backup-2026-03-17.sql.gz
- rclone sync runs as a separate cron job (30-60 min after backup), decoupled from backup script
- rclone config stored in /opt/odoo/ alongside deployment configs (not default /root/.config/rclone/)
- Retention: 7 daily + 4 weekly on local Block Storage, 30 days on Spaces (per requirements)

### Documentation depth & format
- Dual audience: concise for experienced sysadmins, but thorough enough for external contractors/MSPs with zero context on this stack
- Architecture diagram: both ASCII (for terminal reference) and Mermaid (for GitHub rendering)
- Enterprise edition migration doc: full step-by-step guide including backup, image swap, license, module verification, and rollback procedure
- Doc structure: separate files per topic (architecture.md, deployment-runbook.md, operations.md, enterprise-migration.md) PLUS a consolidated operations guide that ties them together

### Claude's Discretion
- Exact backup script implementation details (compression, naming convention, lock handling)
- SMTP configuration approach for failure emails
- Cron timing within the 2-4 AM window
- Status file format for Icinga2 integration
- Consolidated ops guide structure and cross-referencing approach
- Exact verification queries for restore testing

</decisions>

<specifics>
## Specific Ideas

- Backup script follows the existing scripts/ naming convention (NN-verb-noun.sh)
- rclone config lives alongside other deployment config in /opt/odoo/ with restricted permissions (chmod 600)
- Restore script should have a --from-spaces flag for pulling remote backups
- Documentation should work for both the current operator (experienced) and a hypothetical handoff to an MSP

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-backup-recovery-and-documentation*
*Context gathered: 2026-03-17*
