# Phase 3: Backup, Recovery, and Documentation - Research

**Researched:** 2026-03-17
**Domain:** PostgreSQL backup automation, rclone offsite sync, restore verification, deployment/operational documentation
**Confidence:** HIGH

## Summary

Phase 3 delivers automated backup infrastructure, tested restore procedures, and comprehensive documentation for the Odoo 19 production deployment. The technical domain is well-understood: `pg_dump` inside a running PostgreSQL container for database backups, `tar` for Odoo filestore, `rclone` for offsite sync to DO Spaces Cold Storage, and bash scripting with cron for scheduling — all consistent with the project's existing Phase 2 patterns.

The backup script will run as a standalone bash script triggered by system cron, following the `NN-verb-noun.sh` naming convention from Phase 2. rclone syncs to the existing `odoo-prod-backups` Cold Storage bucket (already decided in Phase 1). Restore verification uses a temporary isolated PostgreSQL container — production stays untouched. Documentation covers architecture overview, deployment runbook, operational procedures, and enterprise migration guide as separate files.

**Primary recommendation:** Use `pg_dump` custom format (`-Fc`) for database backups (compressed by default, supports selective restore and parallel restore), `tar -czf` for filestore, `rclone copy` (not sync) for offsite, and `msmtp` as a lightweight MTA for failure email notifications.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Backup includes both PostgreSQL (pg_dump) and Odoo filestore (tar) — NOT deployment configs (those are in git)
- Daily backup runs early morning (2-4 AM) via system cron
- Standalone bash script in scripts/ directory, triggered by cron — consistent with Phase 2 script pattern
- On failure: log to file, send email notification (requires SMTP config), AND write exit code/status files for Phase 5 Icinga2 checks — all three failure reporting mechanisms
- Both automated restore script AND documented manual steps in operational procedures
- Restore verification uses a temporary isolated PG container — production stays untouched during verification
- Thorough verification: DB connects, expected tables exist, key table row counts match, temp Odoo instance boots against restored DB
- Script supports both local backup files AND remote fetch from DO Spaces via rclone (--from-spaces flag)
- Weekly backups are Sunday's daily backup promoted/tagged as weekly — no separate weekly cron job
- DO Spaces bucket organized by year/month directories: 2026/03/odoo-backup-2026-03-17.sql.gz
- rclone sync runs as a separate cron job (30-60 min after backup), decoupled from backup script
- rclone config stored in /opt/odoo/ alongside deployment configs (not default /root/.config/rclone/)
- Retention: 7 daily + 4 weekly on local Block Storage, 30 days on Spaces (per requirements)
- Dual audience documentation: concise for experienced sysadmins, thorough enough for external contractors/MSPs with zero context
- Architecture diagram: both ASCII (for terminal reference) and Mermaid (for GitHub rendering)
- Enterprise edition migration doc: full step-by-step guide including backup, image swap, license, module verification, and rollback procedure
- Doc structure: separate files per topic (architecture.md, deployment-runbook.md, operations.md, enterprise-migration.md) PLUS a consolidated operations guide

### Claude's Discretion
- Exact backup script implementation details (compression, naming convention, lock handling)
- SMTP configuration approach for failure emails
- Cron timing within the 2-4 AM window
- Status file format for Icinga2 integration
- Consolidated ops guide structure and cross-referencing approach
- Exact verification queries for restore testing

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BACK-01 | Automated daily pg_dump to local DO Block Storage Volume | pg_dump via `docker exec` into PostgreSQL container, custom format with compression, written to `/mnt/odoo-prod-data/backups/`. Filestore backup via tar. Cron scheduling at 2:30 AM. |
| BACK-02 | Automated sync of backups to DO Spaces via rclone | rclone with S3 provider type configured for DO Spaces, `rclone copy` to `odoo-prod-backups` Cold Storage bucket, separate cron job at 3:30 AM. Config at `/opt/odoo/rclone.conf`. |
| BACK-03 | Backup retention policy (7 daily, 4 weekly on local; 30 days on Spaces) | Local retention via `find -mtime +N -delete` in backup script. Weekly = Sunday's daily promoted by hard link or copy. Spaces retention via DO Spaces lifecycle policy (30-day expiration rule) or rclone cleanup. |
| BACK-04 | Documented and tested restore procedure with verification script | Restore script with `--from-spaces` flag. Verification via temp PG container: pg_restore, table count comparison, row count spot-checks, temp Odoo boot test. Both scripted and manual procedures documented. |
| DOC-01 | Architecture overview document with network topology diagram | ASCII + Mermaid diagrams showing: Internet -> DO Firewall -> Nginx (host) -> Odoo container <-> PostgreSQL container, VPC, Block Storage, Spaces. Network topology, port mappings, data flows. |
| DOC-02 | Deployment runbook (step-by-step from fresh clone to running Odoo) | End-to-end walkthrough: git clone -> terraform apply -> SCP files -> run scripts 01-04 in order -> verify. Includes prerequisites, secret creation, DNS setup, troubleshooting. |
| DOC-03 | Operational procedures (backup, restore, update Odoo, scale resources) | Covers: manual backup trigger, restore from local/Spaces, Odoo version update (docker pull + compose up), PostgreSQL major version upgrade, droplet resize, volume resize, SSL cert issues. |
| DOC-04 | Short getting-started document for Enterprise edition migration path | Docker image swap from `odoo:19` to enterprise addons bind mount, license activation, web_enterprise module install, verification, rollback procedure. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| pg_dump (in container) | PostgreSQL 18 | Database logical backup | Ships with PostgreSQL image, consistent format, portable across versions |
| tar + gzip | System default | Odoo filestore backup | Universal, no dependencies, efficient for file trees |
| rclone | 1.60+ (Ubuntu apt) or latest (install script) | Offsite sync to DO Spaces | Official DO recommendation, S3-compatible, handles checksums and retries |
| msmtp + msmtp-mta | Ubuntu 24.04 apt | Lightweight SMTP relay for failure emails | Drop-in sendmail replacement, minimal footprint, works with any SMTP provider |
| cron (system) | Ubuntu 24.04 | Backup scheduling | Already available, no additional dependencies, consistent with system patterns |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| pg_restore | PostgreSQL 18 (in container) | Restore custom-format dumps | Required for `-Fc` format backups; supports selective and parallel restore |
| docker compose run | Docker Compose v2 | Spawn temp containers for restore verification | Isolated environment for restore testing without touching production |
| psql (in container) | PostgreSQL 18 | Verification queries post-restore | Table counts, row counts, schema validation |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| pg_dump custom format (`-Fc`) | Plain SQL + gzip | Custom format is compressed by default, supports selective table restore and parallel restore via pg_restore. Plain SQL is human-readable but lacks these features. **Recommendation: custom format.** |
| rclone | s3cmd or aws-cli | rclone is more versatile (supports 40+ backends), has better retry logic, and is the tool recommended by DigitalOcean's own documentation. s3cmd works but has less active development. |
| msmtp | Postfix | msmtp is far simpler for relay-only use (no local delivery needed). Postfix is overkill when you just need to send failure alerts through an external SMTP server. |
| System cron | Systemd timers | Systemd timers offer better logging and dependency management, but cron is simpler, more portable, and consistent with the user's decision for this project. |

**Installation:**
```bash
# On the target host (Ubuntu 24.04)
apt-get install -y rclone msmtp msmtp-mta mailutils
```

Note: `rclone` from Ubuntu 24.04 apt is version 1.60.1. This is sufficient for DO Spaces S3 operations. If newer features are needed, use `curl https://rclone.org/install.sh | sudo bash` instead.

## Architecture Patterns

### Backup File Layout on Block Storage

```
/mnt/odoo-prod-data/
├── postgres-data/           # Live PostgreSQL data (existing)
├── odoo-filestore/          # Live Odoo filestore (existing)
└── backups/
    ├── daily/
    │   ├── odoo-db-2026-03-17.dump       # pg_dump custom format
    │   ├── odoo-files-2026-03-17.tar.gz  # Filestore archive
    │   └── ...                            # Last 7 days
    └── weekly/
        ├── odoo-db-2026-03-16.dump       # Sunday's daily promoted
        ├── odoo-files-2026-03-16.tar.gz
        └── ...                            # Last 4 weeks
```

### DO Spaces Bucket Layout

```
odoo-prod-backups/           # Cold Storage bucket (already provisioned)
└── 2026/
    └── 03/
        ├── odoo-db-2026-03-17.dump
        ├── odoo-files-2026-03-17.tar.gz
        ├── odoo-db-2026-03-16.dump
        └── ...                            # 30-day retention
```

### Script Naming (follows existing convention)

```
scripts/
├── 01-harden-host.sh          # Existing (Phase 2)
├── 02-install-docker.sh       # Existing (Phase 2)
├── 03-deploy-stack.sh         # Existing (Phase 2)
├── 04-setup-nginx.sh          # Existing (Phase 2)
├── 05-setup-backups.sh        # NEW: Install rclone, msmtp, deploy configs, set up cron
├── 06-backup-daily.sh         # NEW: Daily backup script (called by cron)
├── 07-sync-offsite.sh         # NEW: rclone sync to Spaces (called by cron)
└── 08-restore-backup.sh       # NEW: Restore + verification script
```

### Config File Layout

```
config/
├── rclone.conf.example        # NEW: rclone config template for DO Spaces
├── msmtprc.example            # NEW: msmtp config template for SMTP relay
├── backup-cron                # NEW: Cron entries for backup + sync
└── ...                        # Existing configs
```

### Pattern 1: pg_dump via Docker exec (custom format)

**What:** Run pg_dump inside the running PostgreSQL container, pipe output to host filesystem.
**When to use:** Every daily backup execution.

```bash
# Read credentials from .env without sourcing (safe for special chars)
POSTGRES_USER=$(grep '^POSTGRES_USER=' /opt/odoo/.env | cut -d'=' -f2-)
POSTGRES_DB=$(grep '^POSTGRES_DB=' /opt/odoo/.env | cut -d'=' -f2-)

# pg_dump custom format — compressed by default, supports selective restore
docker exec odoo-db pg_dump \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  -Fc \
  --no-owner \
  --no-privileges \
  > "${BACKUP_DIR}/daily/odoo-db-$(date +%Y-%m-%d).dump"
```

**Confidence:** HIGH — docker exec with pg_dump is the standard approach documented by PostgreSQL, Docker, and multiple production guides.

**Key flags:**
- `-Fc`: Custom format (compressed by default, supports pg_restore selective/parallel restore)
- `--no-owner`: Makes backup portable — doesn't require same role names on restore target
- `--no-privileges`: Skips GRANT/REVOKE — avoids permission errors on restore to different environments

### Pattern 2: Odoo Filestore Backup (tar)

**What:** Archive the Odoo filestore directory, excluding sessions subdirectory.
**When to use:** Every daily backup, immediately after pg_dump.

```bash
# Odoo data_dir structure: /var/lib/odoo/{filestore,sessions,addons}
# On host via bind mount: /mnt/odoo-prod-data/odoo-filestore/
# Exclude sessions (ephemeral) and addons (from image)
tar -czf "${BACKUP_DIR}/daily/odoo-files-$(date +%Y-%m-%d).tar.gz" \
  --exclude='sessions' \
  --exclude='addons' \
  -C /mnt/odoo-prod-data \
  odoo-filestore/
```

**Confidence:** HIGH — Odoo's `data_dir` holds three subdirectories: `filestore/` (attachments, must backup), `sessions/` (ephemeral, exclude), and `addons/` (module code from image, exclude).

### Pattern 3: rclone Copy to DO Spaces Cold Storage

**What:** Upload today's backups to the Cold Storage bucket, organized by year/month.
**When to use:** Separate cron job, 30-60 minutes after backup completes.

```bash
RCLONE_CONF="/opt/odoo/rclone.conf"
YEAR=$(date +%Y)
MONTH=$(date +%m)

# Use 'copy' not 'sync' — sync would delete files on remote that aren't local
# (dangerous when local has 7-day retention but remote has 30-day)
rclone copy \
  --config "${RCLONE_CONF}" \
  "${BACKUP_DIR}/daily/" \
  "spaces:odoo-prod-backups/${YEAR}/${MONTH}/" \
  --include "odoo-*-$(date +%Y-%m-%d).*"
```

**Confidence:** HIGH — rclone's S3 provider with DigitalOcean Spaces is well-documented by both rclone and DigitalOcean.

**Critical:** Use `rclone copy` NOT `rclone sync`. `sync` deletes files on the remote that don't exist locally. Since local retention is 7 days but remote is 30 days, `sync` would delete older remote backups.

### Pattern 4: Weekly Promotion (Sunday's daily -> weekly)

**What:** On Sundays, hard-link or copy the daily backup into the weekly directory.
**When to use:** Inside the daily backup script, conditional on day-of-week.

```bash
if [[ "$(date +%u)" == "7" ]]; then
  # Sunday = promote to weekly
  cp -l "${BACKUP_DIR}/daily/odoo-db-${TODAY}.dump" \
        "${BACKUP_DIR}/weekly/odoo-db-${TODAY}.dump" 2>/dev/null \
    || cp "${BACKUP_DIR}/daily/odoo-db-${TODAY}.dump" \
          "${BACKUP_DIR}/weekly/odoo-db-${TODAY}.dump"
  # Same for filestore archive
fi
```

**Note:** `cp -l` creates hard links (no extra disk space) on the same filesystem. Falls back to regular copy if hard links aren't supported.

### Pattern 5: Restore Verification in Temporary Container

**What:** Spin up an isolated PostgreSQL container, restore the backup, run verification queries, tear down.
**When to use:** Restore testing (manual or automated after backup).

```bash
# Start temporary PG container on a different port, not connected to production networks
docker run -d --name odoo-restore-test \
  -e POSTGRES_USER=restore_test \
  -e POSTGRES_PASSWORD=test_only \
  -e POSTGRES_DB=odoo_restore \
  -p 127.0.0.1:5433:5432 \
  postgres:18

# Wait for healthy
sleep 10

# Restore from custom format dump
docker exec -i odoo-restore-test \
  pg_restore -U restore_test -d odoo_restore --no-owner --clean --if-exists \
  < "${BACKUP_FILE}"

# Verify: table count
TABLE_COUNT=$(docker exec odoo-restore-test \
  psql -U restore_test -d odoo_restore -t -c \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")

# Verify: key Odoo tables exist
docker exec odoo-restore-test \
  psql -U restore_test -d odoo_restore -t -c \
  "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN ('res_users','res_partner','crm_lead','project_project') ORDER BY tablename;"

# Verify: row counts for key tables
docker exec odoo-restore-test \
  psql -U restore_test -d odoo_restore -t -c \
  "SELECT 'res_users' AS tbl, count(*) FROM res_users
   UNION ALL SELECT 'res_partner', count(*) FROM res_partner
   UNION ALL SELECT 'crm_lead', count(*) FROM crm_lead;"

# Cleanup
docker stop odoo-restore-test && docker rm odoo-restore-test
```

**Confidence:** HIGH — standard pattern for backup verification. Isolated container ensures zero risk to production.

### Pattern 6: Status File for Icinga2 (Phase 5 preparation)

**What:** Write a simple status file after backup completes (success or failure) that Phase 5 Icinga2 checks can read.
**When to use:** End of every backup script execution.

```bash
STATUS_FILE="/opt/odoo/backup-status.json"

# On success:
cat > "${STATUS_FILE}" << EOF
{
  "status": 0,
  "message": "Backup completed successfully",
  "timestamp": "$(date -Iseconds)",
  "db_size_bytes": ${DB_SIZE},
  "files_size_bytes": ${FILES_SIZE},
  "duration_seconds": ${DURATION}
}
EOF

# On failure:
cat > "${STATUS_FILE}" << EOF
{
  "status": 2,
  "message": "Backup FAILED: ${ERROR_MSG}",
  "timestamp": "$(date -Iseconds)",
  "duration_seconds": ${DURATION}
}
EOF
```

**Format rationale:** JSON for easy parsing by Icinga2 check scripts. `status` uses Nagios convention: 0=OK, 1=WARNING, 2=CRITICAL. Phase 5 Icinga2 check reads this file and reports to master.

### Anti-Patterns to Avoid

- **Running pg_dump from the host:** The host doesn't have pg_dump installed (PostgreSQL runs in a container). Always use `docker exec` to run pg_dump inside the container where the correct version is guaranteed.
- **Using `source .env` to read credentials:** Passwords with special characters (`!`, `#`, `&`) break bash sourcing. Use `grep + cut` to extract values safely (pattern established in 03-deploy-stack.sh).
- **Using `rclone sync` for offsite backups:** `sync` deletes remote files not present locally. With 7-day local retention and 30-day remote retention, `sync` would destroy older remote backups. Use `rclone copy` instead.
- **Backing up live PostgreSQL data directory via tar/rsync:** File-level backup of a running PostgreSQL instance produces inconsistent data. Always use pg_dump for logical backups.
- **Running restore verification against production database:** Always use a separate temporary container. Never restore test data into the production PostgreSQL instance.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| S3-compatible offsite sync | Custom curl/boto3 scripts | rclone | Handles retries, checksums, multipart upload, config management |
| Email delivery from server | Direct SMTP socket code | msmtp | Drop-in sendmail replacement, handles TLS, auth, relay configuration |
| Backup scheduling | Custom daemon or sleep loops | System cron | Battle-tested, survives reboots, syslog integration |
| PostgreSQL dump format | Custom SQL generation | pg_dump `-Fc` | Handles all data types, large objects, encoding, compression natively |
| Compression | Custom streaming compression | gzip (tar -czf) or pg_dump built-in | Standard, tested, predictable compression ratios |

**Key insight:** Every component of backup infrastructure has a mature, well-tested standard tool. The value is in correct orchestration and error handling, not in reimplementing any individual piece.

## Common Pitfalls

### Pitfall 1: Credential Sourcing with Special Characters
**What goes wrong:** `source .env` or `. .env` breaks when passwords contain `!`, `$`, backticks, or other bash metacharacters.
**Why it happens:** Bash interprets these characters during sourcing.
**How to avoid:** Use `grep '^KEY=' file | cut -d'=' -f2-` to extract values as raw strings. This pattern is already established in `03-deploy-stack.sh`.
**Warning signs:** Backup script fails with "unexpected token" or "bad substitution" errors that only appear with certain passwords.

### Pitfall 2: rclone sync Deleting Remote Backups
**What goes wrong:** `rclone sync` removes files from the remote that don't exist locally, destroying backups older than local retention.
**Why it happens:** `sync` makes remote match local exactly. With 7-day local retention and 30-day remote retention, files aged off locally get deleted remotely.
**How to avoid:** Use `rclone copy` which only uploads new/changed files without deleting anything on the remote.
**Warning signs:** Remote backup count never exceeds local count. 30-day-old backups missing from Spaces.

### Pitfall 3: Cold Storage 30-Day Minimum Charge
**What goes wrong:** Frequent overwrites or deletions on DO Spaces Cold Storage incur early deletion charges.
**Why it happens:** Cold Storage has a 30-day minimum storage charge per object. Deleting or overwriting an object before 30 days means you pay for the full 30 days anyway.
**How to avoid:** Use `rclone copy` (no overwrites), and let the 30-day Spaces lifecycle rule handle deletions. Never manually delete recent Cold Storage objects.
**Warning signs:** Higher-than-expected Spaces billing despite low actual storage usage.

### Pitfall 4: Backup Script Running During Docker Restart
**What goes wrong:** If Docker daemon or PostgreSQL container restarts during pg_dump, the backup is corrupted or incomplete.
**Why it happens:** Docker daemon restart kills all containers; pg_dump connection drops mid-dump.
**How to avoid:** Check container health before starting backup. Write to a temp file first, then rename on success. Check pg_dump exit code before considering backup complete.
**Warning signs:** Truncated dump files, pg_restore errors on seemingly valid backups.

### Pitfall 5: Disk Space Exhaustion During Backup
**What goes wrong:** Backup fills the Block Storage Volume, which also holds live PostgreSQL data and Odoo filestore.
**Why it happens:** Backups share the same volume as production data. If retention cleanup fails or database grows unexpectedly, free space runs out.
**How to avoid:** Check available disk space before starting backup (fail if below threshold). Run retention cleanup BEFORE creating new backup. Monitor volume usage (Phase 5 Icinga2 check).
**Warning signs:** Write errors in PostgreSQL logs, Odoo unable to save attachments, backup script failing silently.

### Pitfall 6: msmtp Failing Silently
**What goes wrong:** Email notifications don't arrive but the backup script doesn't know.
**Why it happens:** msmtp fails (bad credentials, SMTP server down) but the script doesn't check its exit code.
**How to avoid:** Check msmtp exit code and log the failure. The status file for Icinga2 serves as a secondary notification path.
**Warning signs:** No email alerts for weeks, status file shows failures that were never reported.

### Pitfall 7: PostgreSQL 18 PGDATA Path Change
**What goes wrong:** This project explicitly sets `PGDATA: /var/lib/postgresql/data/pgdata` in docker-compose.yml, which overrides the PostgreSQL 18 default of `/var/lib/postgresql/18/docker`. This is fine for pg_dump (uses database connection, not file paths), but matters for any file-level operations.
**Why it happens:** PostgreSQL 18 Docker image changed the default PGDATA path to be version-specific.
**How to avoid:** Always use pg_dump (logical backup via database connection) rather than file-level backup. The PGDATA path doesn't affect pg_dump.
**Warning signs:** Only relevant if someone attempts file-level backup of the data directory.

## Code Examples

### rclone.conf for DO Spaces

```ini
# /opt/odoo/rclone.conf
# Config for rclone offsite backup sync to DO Spaces Cold Storage
# Credentials: DO Spaces access key (NOT the main API token)

[spaces]
type = s3
provider = DigitalOcean
env_auth = false
access_key_id = SPACES_ACCESS_KEY_PLACEHOLDER
secret_access_key = SPACES_SECRET_KEY_PLACEHOLDER
endpoint = nyc3.digitaloceanspaces.com
acl = private
```

**Note:** The endpoint region must match the bucket's region (nyc3 per `infra/variables.tf` default). Access keys are Spaces-specific keys, separate from the DigitalOcean API token.

### msmtp Configuration

```ini
# /opt/odoo/msmtprc
# Lightweight SMTP relay for backup failure notifications

defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           SMTP_HOST_PLACEHOLDER
port           587
from           SMTP_FROM_PLACEHOLDER
user           SMTP_USER_PLACEHOLDER
password       SMTP_PASSWORD_PLACEHOLDER
```

### Cron Entries

```cron
# /etc/cron.d/odoo-backup
# BACK-01: Daily backup at 2:30 AM
30 2 * * * root /opt/odoo/scripts/06-backup-daily.sh >> /var/log/odoo-backup.log 2>&1

# BACK-02: Offsite sync at 3:30 AM (1 hour after backup)
30 3 * * * root /opt/odoo/scripts/07-sync-offsite.sh >> /var/log/odoo-backup-sync.log 2>&1
```

### Restore Script Usage Pattern

```bash
# Restore from most recent local backup
sudo bash scripts/08-restore-backup.sh

# Restore from a specific local backup
sudo bash scripts/08-restore-backup.sh --file /mnt/odoo-prod-data/backups/daily/odoo-db-2026-03-15.dump

# Restore from DO Spaces (fetches via rclone)
sudo bash scripts/08-restore-backup.sh --from-spaces --date 2026-03-10

# Verify-only mode (temp container, don't touch production)
sudo bash scripts/08-restore-backup.sh --verify-only

# Full restore to production (stops Odoo, restores, restarts)
sudo bash scripts/08-restore-backup.sh --production
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| pg_dump plain SQL | pg_dump custom format (`-Fc`) | Long-standing best practice | Compressed by default, supports pg_restore selective/parallel restore |
| pg_dump `-Z` for compression | Built-in compression in `-Fc` | PostgreSQL 16+ enhanced compression options | `-Fc` compresses by default; explicit `-Z` allows tuning level (0-9) |
| Manual rclone config | `rclone config` with provider presets | rclone 1.50+ | DO Spaces is a known provider; `rclone config` wizard handles setup |
| Postfix for server email | msmtp as lightweight relay | Trend over last 5+ years | msmtp is far simpler when only outbound relay is needed |
| Nagios external command file | Icinga2 API for passive checks | Icinga2 2.x | Both work; file-based approach is simpler for this use case and doesn't require API credentials |

**Deprecated/outdated:**
- `pg_dumpall` for single-database backups: Use `pg_dump` for individual databases. `pg_dumpall` is only needed for globals (roles, tablespaces) — not relevant here since PostgreSQL runs in a dedicated container with a single database.
- `/root/.config/rclone/rclone.conf` default location: User decision places config at `/opt/odoo/rclone.conf` with `--config` flag. This is better for security (single location, explicit chmod 600) and discoverability.

## Open Questions

1. **SMTP Provider for Email Alerts**
   - What we know: msmtp needs an SMTP relay (Gmail, SendGrid, Mailgun, or any SMTP server). The project doesn't specify which provider.
   - What's unclear: Which SMTP service will be used. Credentials need to be added to deployment.
   - Recommendation: Add SMTP credentials to `.env.example` as placeholders. The setup script configures msmtp from these. Common choices: existing business email SMTP, SendGrid free tier (100 emails/day), or Mailgun.

2. **DO Spaces Lifecycle Rules for 30-Day Retention**
   - What we know: DO Spaces supports lifecycle rules to auto-delete objects after N days. This is configured via the Spaces API or S3 CLI.
   - What's unclear: Whether to use a lifecycle rule (server-side, automatic) or rclone-based cleanup (client-side, in sync script).
   - Recommendation: Use a DO Spaces lifecycle rule for 30-day expiration. Server-side is more reliable (runs even if the host is down) and doesn't require additional script logic. Can be set via `s3cmd` or the DO API.

3. **Exact Backup Size Estimates**
   - What we know: Fresh Odoo install with CRM + Project modules. Database is small initially.
   - What's unclear: Growth rate over time with 10 users.
   - Recommendation: Start with conservative estimates. A fresh Odoo database is ~50-100MB uncompressed, ~10-20MB compressed. Filestore grows with attachments. 25GB Block Storage volume has ample headroom for months of backups plus production data.

4. **Enterprise Migration: Odoo Private Registry Access**
   - What we know: Enterprise Docker image is NOT on Docker Hub. Requires Odoo Enterprise subscription, then either pull from Odoo's private registry or build custom image with enterprise addons as bind mount.
   - What's unclear: Exact registry URL and authentication method (may change between versions).
   - Recommendation: Document the bind-mount approach (mount enterprise addons directory into community image) as it's more portable and doesn't depend on registry access. Reference official Odoo 19 docs: https://www.odoo.com/documentation/19.0/administration/on_premise/community_to_enterprise.html

## Sources

### Primary (HIGH confidence)
- [PostgreSQL 18 pg_dump documentation](https://www.postgresql.org/docs/current/app-pgdump.html) — format options, compression, flags
- [PostgreSQL 18 pg_restore documentation](https://www.postgresql.org/docs/current/app-pgrestore.html) — restore from custom format
- [rclone S3 provider documentation](https://rclone.org/s3/) — DigitalOcean Spaces configuration
- [DigitalOcean: Migrate with rclone](https://www.digitalocean.com/community/tutorials/how-to-migrate-from-amazon-s3-to-digitalocean-spaces-with-rclone) — rclone + DO Spaces setup
- [DigitalOcean Spaces lifecycle rules](https://docs.digitalocean.com/products/spaces/how-to/configure-lifecycle-rules/) — server-side retention
- [Odoo 19 Community to Enterprise](https://www.odoo.com/documentation/19.0/administration/on_premise/community_to_enterprise.html) — official migration guide
- [PostgreSQL 18 Docker PGDATA change](https://github.com/docker-library/postgres/pull/1259) — version-specific data directory

### Secondary (MEDIUM confidence)
- [Docker Postgres Backup Guide (SimpleBackups)](https://simplebackups.com/blog/docker-postgres-backup-restore-guide-with-examples) — docker exec patterns
- [PostgreSQL Automated Backup on Linux (PG Wiki)](https://wiki.postgresql.org/wiki/Automated_Backup_on_Linux) — retention rotation patterns
- [PostgreSQL backup verification (pgDash)](https://pgdash.io/blog/testing-postgres-backups.html) — automated verification approach
- [Odoo filestore structure (KoderStory)](https://devlog.koderstory.com/understanding-odoos-filestore-structure-whats-inside-and-why-it-matters) — data_dir subdirectories
- [rclone install page](https://rclone.org/install/) — installation methods for Ubuntu
- [Ubuntu 24.04 rclone package](https://launchpad.net/ubuntu/noble/+source/rclone) — apt package version

### Tertiary (LOW confidence)
- Cron timing recommendations (2-4 AM): general best practice, validated by user decision
- msmtp vs Postfix for relay-only: community consensus, not benchmarked for this specific setup

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — pg_dump, rclone, msmtp, tar, cron are all mature, well-documented tools
- Architecture: HIGH — patterns are consistent with existing Phase 2 conventions (script naming, config deployment, credential handling)
- Pitfalls: HIGH — sourced from PostgreSQL docs, rclone docs, and real-world Docker backup experience
- Documentation patterns: MEDIUM — doc structure is user-decided; content quality depends on execution

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (30 days — stable domain, no fast-moving dependencies)
