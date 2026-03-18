# Enterprise Edition Migration Guide

Step-by-step guide for migrating from Odoo Community 19.x to Odoo Enterprise 19.x. This is a non-destructive process with a tested rollback path.

**Reference:** [Odoo 19 Community to Enterprise](https://www.odoo.com/documentation/19.0/administration/on_premise/community_to_enterprise.html)

## Prerequisites

Before starting the migration:

- [ ] Active Odoo Enterprise subscription (purchase at [odoo.com](https://www.odoo.com/pricing))
- [ ] Enterprise addons source -- either:
  - Download from your Odoo account portal, OR
  - Access to Odoo's private Docker registry (provided with subscription)
- [ ] Current system backup verified and tested (see Pre-Migration Backup below)
- [ ] SSH access to the droplet as `deploy` user
- [ ] At least 2 GB free disk space on the Block Storage Volume
- [ ] Maintenance window scheduled (expect 15-30 minutes of downtime)

## Pre-Migration Backup

A verified backup is mandatory before proceeding. This is your safety net.

### 1. Run a full backup

```bash
sudo /opt/odoo/scripts/06-backup-daily.sh
```

### 2. Verify the backup (non-destructive)

This spins up a temporary PostgreSQL container, restores the backup, runs validation queries, and tears down -- production is untouched.

```bash
sudo bash /opt/odoo/scripts/08-restore-backup.sh --verify-only
```

Expected output: table counts, row counts for key tables, and a PASS/FAIL summary.

### 3. Confirm backup exists in DO Spaces

Either wait for the scheduled rclone sync (3:30 AM) or trigger it manually:

```bash
sudo /opt/odoo/scripts/07-sync-offsite.sh
```

Verify the remote backup:

```bash
rclone ls --config /opt/odoo/rclone.conf spaces:odoo-prod-backups/$(date +%Y)/$(date +%m)/ | grep "$(date +%Y-%m-%d)"
```

### 4. Record the current state

Note these values before migration -- you will verify them after:

```bash
# Odoo version
docker exec odoo-app odoo --version

# Database row counts for key tables
docker exec odoo-db psql -U odoo -d odoo -c \
  "SELECT 'res_users' AS tbl, count(*) FROM res_users
   UNION ALL SELECT 'res_partner', count(*) FROM res_partner
   UNION ALL SELECT 'crm_lead', count(*) FROM crm_lead
   UNION ALL SELECT 'project_project', count(*) FROM project_project;"
```

## Migration Steps

### Step 1: Stop the Odoo container

```bash
cd /opt/odoo
docker compose stop odoo
```

PostgreSQL stays running -- we only need to stop Odoo.

### Step 2: Obtain Enterprise addons

Download the Enterprise addons for Odoo 19 from your Odoo account portal. Transfer them to the droplet:

```bash
# From your local machine
scp -P 9292 odoo-enterprise-19.0.tar.gz deploy@<droplet-ip>:/tmp/

# On the droplet
sudo mkdir -p /opt/odoo/enterprise
sudo tar -xzf /tmp/odoo-enterprise-19.0.tar.gz -C /opt/odoo/enterprise --strip-components=1
sudo chown -R 101:101 /opt/odoo/enterprise
```

The directory should contain addon folders like `web_enterprise/`, `crm_enterprise/`, etc.

### Step 3: Update docker-compose.yml

Add the enterprise addons bind mount to the Odoo service:

```yaml
# In /opt/odoo/docker-compose.yml, under the odoo service volumes:
volumes:
  - /mnt/odoo-prod-data/odoo-filestore:/var/lib/odoo
  - ./odoo.conf:/etc/odoo/odoo.conf:ro
  - ./enterprise:/mnt/extra-addons:ro    # <-- ADD THIS LINE
```

### Step 4: Update odoo.conf

Add the enterprise addons path. Edit `/opt/odoo/odoo.conf`:

```ini
; Add enterprise addons path BEFORE the standard addons path
; Odoo searches paths left-to-right; enterprise overrides community modules
addons_path = /mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
```

### Step 5: Start the Odoo container

```bash
cd /opt/odoo
docker compose up -d odoo
```

Wait for the health check to pass:

```bash
docker compose ps
# odoo-app should show "healthy" within ~60 seconds
```

### Step 6: Install the web_enterprise module

Option A -- Via the Odoo UI:
1. Navigate to `https://<domain>/web#action=base.open_module_tree`
2. Search for "web_enterprise"
3. Click Install

Option B -- Via CLI:
```bash
docker compose run --rm odoo odoo -d odoo -i web_enterprise --stop-after-init
docker compose restart odoo
```

### Step 7: Activate the Enterprise license

1. Log in to Odoo as the administrator
2. Navigate to **Settings** (gear icon)
3. Look for **Odoo Enterprise License** or **Database Registration**
4. Enter your Enterprise subscription code
5. Click **Register** or **Activate**

### Step 8: Verify Enterprise features

After activation, confirm the Enterprise edition is active:

```bash
# Container logs should not show licensing warnings
docker logs odoo-app --tail 20
```

In the Odoo UI, verify:
- Settings page shows "Odoo Enterprise" branding (not "Odoo Community")
- Enterprise-specific features are available in installed modules

## Verification Checklist

After migration, verify all of the following:

- [ ] Enterprise dashboard visible (Settings shows Enterprise branding)
- [ ] All existing CRM leads are intact (compare row counts from pre-migration)
- [ ] All existing Project tasks are intact
- [ ] All user logins work (test with at least 2 accounts)
- [ ] File attachments are accessible (open a record with attachments)
- [ ] SSL certificate still valid: `curl -I https://<domain>` shows HSTS header
- [ ] Odoo health check passes: `curl -fsS http://localhost:8069/web/health`
- [ ] Backup runs successfully: `sudo /opt/odoo/scripts/06-backup-daily.sh`

## Rollback Procedure

If anything goes wrong, you can revert to Community edition.

### Quick rollback (no data changes by Enterprise modules)

If you installed `web_enterprise` but Enterprise modules have not modified any data:

```bash
cd /opt/odoo

# 1. Stop Odoo
docker compose stop odoo

# 2. Remove enterprise bind mount from docker-compose.yml
# Delete the line: - ./enterprise:/mnt/extra-addons:ro

# 3. Revert odoo.conf addons_path
# Remove /mnt/extra-addons from the addons_path line

# 4. Start Odoo
docker compose up -d odoo

# 5. Verify Community edition is running
docker logs odoo-app --tail 20
```

### Full rollback (Enterprise modules modified data)

If Enterprise modules have created new records, changed schemas, or modified existing data, a config-only rollback is not safe. Restore from the pre-migration backup:

```bash
# Full production restore from the backup taken before migration
sudo bash /opt/odoo/scripts/08-restore-backup.sh --production --file /mnt/odoo-prod-data/backups/daily/odoo-db-<DATE>.dump

# Also revert docker-compose.yml and odoo.conf as described in Quick Rollback above
```

This restores the database to its exact pre-migration state.

## Notes

### Enterprise Docker Image alternative

Odoo provides a private Docker registry for Enterprise subscribers. Instead of using the Community image with a bind mount, you can pull the Enterprise image directly:

```yaml
# Alternative: replace odoo:19 with the Enterprise image
image: odoo:19-enterprise
# Registry access requires authentication provided with your subscription
```

The bind-mount approach documented above is more portable and does not depend on private registry access.

### Version compatibility

- Enterprise addons **must match** the Community version exactly (both Odoo 19)
- Minor version mismatches between addons and the base image can cause module loading errors
- When updating Odoo, update both the Docker image and the enterprise addons together

### Support contacts

- **Odoo Enterprise support:** [odoo.com/help](https://www.odoo.com/help) (included with subscription)
- **DigitalOcean support:** [cloud.digitalocean.com/support](https://cloud.digitalocean.com/support)
- **Infrastructure issues:** Check [docs/operations.md](operations.md) for troubleshooting procedures

---

*Requirement coverage: DOC-04*
*Last updated: 2026-03-17*
