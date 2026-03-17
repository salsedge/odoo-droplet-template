# Operational Procedures

Day-to-day management procedures for the Odoo 19.x production deployment. Each section is self-contained -- jump to the procedure you need.

**Connection info:**

```bash
ssh -p 9292 deploy@<droplet-ip>
```

All commands below assume you are logged in as the `deploy` user with sudo access.

## 1. Backup Operations

### How automated backups work

Two cron jobs run daily (in `/etc/cron.d/odoo-backup`):

| Time | Script | What it does |
|------|--------|--------------|
| 2:30 AM | `06-backup-daily.sh` | pg_dump (database) + tar (filestore) to local Block Storage |
| 3:30 AM | `07-sync-offsite.sh` | rclone copy of today's backup to DO Spaces Cold Storage |

**Retention:**
- Local (Block Storage): 7 daily + 4 weekly
- Remote (DO Spaces): 30 days (managed by Spaces lifecycle rule)
- Weekly = Sunday's daily backup promoted to `weekly/` directory

### Manual backup

```bash
sudo /opt/odoo/scripts/06-backup-daily.sh
```

This creates:
- `/mnt/odoo-prod-data/backups/daily/odoo-db-YYYY-MM-DD.dump` (PostgreSQL custom format)
- `/mnt/odoo-prod-data/backups/daily/odoo-files-YYYY-MM-DD.tar.gz` (Odoo filestore)

### Check backup status

The backup script writes a JSON status file after each run:

```bash
cat /opt/odoo/backup-status.json
```

```json
{
  "status": 0,
  "message": "Backup completed successfully",
  "timestamp": "2026-03-17T02:31:45+00:00",
  "db_size_bytes": 15728640,
  "files_size_bytes": 8388608,
  "duration_seconds": 12
}
```

Status codes follow Nagios convention: 0=OK, 1=WARNING, 2=CRITICAL.

### List local backups

```bash
# Daily backups
ls -la /mnt/odoo-prod-data/backups/daily/

# Weekly backups
ls -la /mnt/odoo-prod-data/backups/weekly/
```

### List remote backups (DO Spaces)

```bash
rclone ls --config /opt/odoo/rclone.conf spaces:odoo-prod-backups/
```

### Manually trigger offsite sync

```bash
sudo /opt/odoo/scripts/07-sync-offsite.sh
```

### Check backup disk usage

```bash
du -sh /mnt/odoo-prod-data/backups/daily/
du -sh /mnt/odoo-prod-data/backups/weekly/
df -h /mnt/odoo-prod-data/
```

## 2. Restore Operations

### Verify a backup (non-destructive)

Spins up a temporary PostgreSQL container, restores the backup, runs validation queries, tears down. **Production is not affected.**

```bash
# Verify the most recent local backup
sudo bash /opt/odoo/scripts/08-restore-backup.sh --verify-only

# Verify a specific backup file
sudo bash /opt/odoo/scripts/08-restore-backup.sh --verify-only \
  --file /mnt/odoo-prod-data/backups/daily/odoo-db-2026-03-15.dump
```

The verification checks:
- Database connection to restored dump
- Expected Odoo tables exist (res_users, res_partner, crm_lead, project_project)
- Row counts for key tables
- Temporary Odoo container boots against the restored database

### Restore a specific local backup to production

**Warning:** This stops Odoo, drops the current database, and restores from backup. All data since the backup will be lost.

```bash
sudo bash /opt/odoo/scripts/08-restore-backup.sh --production \
  --file /mnt/odoo-prod-data/backups/daily/odoo-db-2026-03-15.dump
```

### Restore from DO Spaces (remote backup)

Fetches the backup from DO Spaces via rclone, then restores to production:

```bash
sudo bash /opt/odoo/scripts/08-restore-backup.sh --production \
  --from-spaces --date 2026-03-10
```

### Post-restore verification

After any production restore:

1. Check Odoo is running:
   ```bash
   docker compose -f /opt/odoo/docker-compose.yml ps
   curl -fsS http://localhost:8069/web/health
   ```

2. Log in to the Odoo UI and verify:
   - User logins work
   - CRM leads are present
   - Project tasks are present
   - File attachments open correctly

3. Run a new backup immediately:
   ```bash
   sudo /opt/odoo/scripts/06-backup-daily.sh
   ```

## 3. Odoo Version Update

### Pre-update checklist

- [ ] Run and verify a full backup
- [ ] Note current Odoo version: `docker exec odoo-app odoo --version`
- [ ] Check the [Odoo 19 release notes](https://www.odoo.com/documentation/19.0/developer/reference/upgrades.html) for breaking changes
- [ ] Schedule a maintenance window

### Update procedure

```bash
cd /opt/odoo

# Pull the new image
docker pull odoo:19

# Check the new image version
docker inspect odoo:19 | grep -i version

# Recreate the Odoo container with the new image
docker compose up -d odoo

# Wait for health check
docker compose ps
# odoo-app should show "healthy" within ~60 seconds
```

### Post-update verification

```bash
# Check Odoo version
docker exec odoo-app odoo --version

# Test the health endpoint
curl -fsS http://localhost:8069/web/health

# Check for errors in logs
docker logs odoo-app --tail 50
```

Log in to the Odoo UI and verify CRM, Project, and other modules work correctly.

### Rollback an Odoo update

If the update causes issues:

```bash
cd /opt/odoo

# Stop the updated container
docker compose stop odoo

# Restore from the pre-update backup
sudo bash /opt/odoo/scripts/08-restore-backup.sh --production \
  --file /mnt/odoo-prod-data/backups/daily/odoo-db-<pre-update-date>.dump

# Pull the previous image tag (if known)
# docker pull odoo:19.0.YYYY.MM.DD

# Start with restored database
docker compose up -d odoo
```

If the specific previous image tag is not available, the database restore alone may not be sufficient -- the new image version may have applied database migrations. In that case, you may need to restore both the database and pin the image to a specific digest.

## 4. PostgreSQL Major Version Upgrade

**Warning:** Major version upgrades (e.g., PostgreSQL 18 to 19) require a dump/restore cycle. The on-disk data format is not compatible between major versions.

### Upgrade procedure

```bash
cd /opt/odoo

# 1. Full backup (mandatory)
sudo /opt/odoo/scripts/06-backup-daily.sh
sudo bash /opt/odoo/scripts/08-restore-backup.sh --verify-only

# 2. Stop all containers
docker compose down

# 3. Update the image tag in docker-compose.yml
# Change: image: postgres:18
# To:     image: postgres:19

# 4. Remove the old PostgreSQL data directory
# WARNING: This deletes all database data. You MUST have a verified backup.
sudo rm -rf /mnt/odoo-prod-data/postgres-data/*

# 5. Start the new PostgreSQL container (creates fresh data directory)
docker compose up -d db

# Wait for healthy
docker compose ps

# 6. Restore the database from backup
sudo bash /opt/odoo/scripts/08-restore-backup.sh --production \
  --file /mnt/odoo-prod-data/backups/daily/odoo-db-$(date +%Y-%m-%d).dump

# 7. Start Odoo
docker compose up -d odoo

# 8. Verify
docker compose ps
curl -fsS http://localhost:8069/web/health
```

### Post-upgrade verification

```bash
# Check PostgreSQL version
docker exec odoo-db psql -U odoo -d odoo -c "SELECT version();"

# Check table counts match pre-upgrade
docker exec odoo-db psql -U odoo -d odoo -c \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';"
```

## 5. Droplet Resize (Vertical Scaling)

### Option A: Via Terraform (recommended)

Edit `infra/terraform.tfvars`:

```hcl
droplet_size = "s-4vcpu-8gb"  # Was: s-2vcpu-4gb
```

Apply:

```bash
cd infra
terraform plan   # Review -- should show droplet resize
terraform apply
```

Note: Terraform may need to power off the droplet to resize. This causes downtime.

### Option B: Via DigitalOcean Console

1. Go to [cloud.digitalocean.com](https://cloud.digitalocean.com) -> Droplets -> your droplet
2. Power off the droplet
3. Click Resize -> select new size
4. Power on

**Important:** If you resize via the DO console, update `terraform.tfvars` to match. Otherwise the next `terraform apply` will revert the change.

### After resize: adjust Odoo workers

If CPU count increased, update the worker count in `/opt/odoo/odoo.conf`:

```ini
; Odoo worker formula: (2 * CPU) + 1
; 2 vCPU -> 3 workers (current)
; 4 vCPU -> 5 workers (after resize to s-4vcpu-8gb)
workers = 5
```

Update memory limits if RAM increased significantly:

```ini
; For 8 GB total, container limit ~4 GB
limit_memory_soft = 1073741824   ; 1 GB per worker
limit_memory_hard = 1610612736   ; 1.5 GB per worker
```

Restart Odoo to apply:

```bash
cd /opt/odoo
docker compose restart odoo
```

Also consider updating container resource limits in `docker-compose.yml` if the droplet has more RAM/CPU.

## 6. Volume Resize (Storage Scaling)

### Expand via Terraform

Edit `infra/terraform.tfvars`:

```hcl
volume_size_gb = 50  # Was: 25
```

Apply:

```bash
cd infra
terraform plan
terraform apply
```

### Expand the filesystem on the droplet

Terraform resizes the block device, but the filesystem needs to be expanded:

```bash
# Identify the volume device
lsblk

# Expand ext4 filesystem (online, no downtime)
sudo resize2fs /dev/disk/by-id/scsi-0DO_Volume_odoo-prod-data

# Verify new size
df -h /mnt/odoo-prod-data/
```

`resize2fs` on ext4 can run online (while mounted) without downtime.

## 7. SSL Certificate Issues

### Check certificate status

```bash
sudo certbot certificates
```

This shows the domain, expiry date, and certificate path.

### Force certificate renewal

```bash
sudo certbot renew --force-renewal
sudo systemctl reload nginx
```

### Check the renewal timer

Certbot auto-renewal is managed by a systemd timer that runs twice daily with a random delay:

```bash
sudo systemctl status certbot.timer
sudo systemctl list-timers | grep certbot
```

### Full certificate reissue

If the certificate is corrupted or the domain changed:

```bash
# Delete the old certificate
sudo certbot delete --cert-name yourdomain.com

# Reissue (ensure port 80 is accessible and DNS points to this server)
sudo certbot certonly --webroot -w /var/www/certbot \
  -d yourdomain.com --non-interactive --agree-tos \
  -m admin@youremail.com

# Reload Nginx
sudo systemctl reload nginx
```

### Certificate troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Certificate expired" in browser | Renewal failed silently | `sudo certbot renew --force-renewal` |
| Renewal timer not running | systemd timer disabled | `sudo systemctl enable --now certbot.timer` |
| HTTP-01 challenge fails | Port 80 blocked | Check UFW: `sudo ufw status`, check cloud firewall |
| OCSP stapling errors in Nginx | DNS resolver unreachable | Verify `resolver 1.1.1.1 1.0.0.1` in Nginx config |

## 8. Log Locations

### Application logs

```bash
# Odoo application logs (stdout from container)
docker logs odoo-app
docker logs --tail 100 -f odoo-app       # Follow last 100 lines

# PostgreSQL logs
docker logs odoo-db
docker logs --tail 100 -f odoo-db
```

### Web server logs

```bash
# Nginx access log (all HTTP requests)
sudo tail -f /var/log/nginx/odoo-access.log

# Nginx error log (proxy errors, upstream timeouts)
sudo tail -f /var/log/nginx/odoo-error.log
```

### Backup logs

```bash
# Daily backup log
sudo tail -f /var/log/odoo-backup.log

# Offsite sync log
sudo tail -f /var/log/odoo-backup-sync.log

# Backup status (JSON, machine-readable)
cat /opt/odoo/backup-status.json
```

### System and security logs

```bash
# SSH and authentication (systemd journal)
journalctl -u ssh
journalctl -u ssh --since "1 hour ago"

# fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client status odoo-login

# fail2ban log
sudo tail -f /var/log/fail2ban.log

# auditd log (PCI-DSS events)
sudo ausearch -k root-commands --start today
sudo ausearch -k identity --start today

# System journal (all services)
journalctl -f
journalctl --since "1 hour ago" --priority err

# Kernel messages
dmesg --human --follow
```

### Docker daemon logs

```bash
journalctl -u docker
journalctl -u docker --since "1 hour ago"
```

### SMTP relay log

```bash
sudo tail -f /var/log/msmtp.log
```

## 9. Emergency Procedures

### Odoo is down (container stopped or crashed)

```bash
# Check container status
docker compose -f /opt/odoo/docker-compose.yml ps

# If stopped, restart
docker compose -f /opt/odoo/docker-compose.yml restart odoo

# If not starting, check logs
docker logs odoo-app --tail 50

# Nuclear option: recreate the container (pulls fresh from image)
docker compose -f /opt/odoo/docker-compose.yml up -d --force-recreate odoo
```

### Database connection issues

```bash
# Check PostgreSQL health
docker exec odoo-db pg_isready -U odoo

# If not ready, check logs
docker logs odoo-db --tail 50

# Restart PostgreSQL
docker compose -f /opt/odoo/docker-compose.yml restart db

# After DB restart, restart Odoo too (to reconnect)
docker compose -f /opt/odoo/docker-compose.yml restart odoo
```

### Disk full

```bash
# Check disk usage
df -h /mnt/odoo-prod-data/
du -sh /mnt/odoo-prod-data/*/

# Check Docker log sizes (rotation should handle this, but verify)
sudo du -sh /var/lib/docker/containers/*/

# If backups are consuming too much space, clean old ones manually
ls -la /mnt/odoo-prod-data/backups/daily/
# Remove oldest files as needed

# If Docker logs are oversized (rotation failed)
sudo truncate -s 0 /var/lib/docker/containers/<container-id>/<container-id>-json.log
```

**Long-term fix:** Expand the volume (see Section 6: Volume Resize).

### Locked out of SSH

1. **Access via DigitalOcean web console:** Droplets -> your droplet -> Console (provides direct terminal access, bypasses SSH)

2. **Check fail2ban:**
   ```bash
   sudo fail2ban-client status sshd
   # If your IP is banned:
   sudo fail2ban-client set sshd unbanip YOUR.IP.ADDRESS
   ```

3. **Check UFW:**
   ```bash
   sudo ufw status
   # If port 9292 is missing:
   sudo ufw allow 9292/tcp
   ```

4. **Check sshd is running:**
   ```bash
   sudo systemctl status ssh
   sudo systemctl restart ssh
   ```

### Nginx returning 502 for all requests

```bash
# Check if Odoo container is running and healthy
docker compose -f /opt/odoo/docker-compose.yml ps

# Check if Odoo is listening on expected ports
sudo ss -tlnp | grep -E '8069|8072'

# Check Nginx configuration is valid
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx

# If Odoo is not responding on 8069, restart it
docker compose -f /opt/odoo/docker-compose.yml restart odoo
```

### Complete system restart (after reboot or power loss)

Docker containers are configured with `restart: unless-stopped`, so they should auto-start. Verify:

```bash
# Check all containers are up
docker compose -f /opt/odoo/docker-compose.yml ps

# Check services
sudo systemctl status nginx
sudo systemctl status docker
sudo systemctl status fail2ban
sudo systemctl status ufw

# If Odoo containers didn't start
docker compose -f /opt/odoo/docker-compose.yml up -d

# Check Nginx is proxying correctly
curl -fsS http://localhost:8069/web/health
curl -I https://yourdomain.com
```

---

*Requirement coverage: DOC-03*
*Last updated: 2026-03-17*
