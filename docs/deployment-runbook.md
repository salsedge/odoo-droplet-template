# Deployment Runbook

End-to-end guide for deploying Odoo 19.x from a fresh git clone to a running production instance on DigitalOcean. Estimated time: ~45 minutes.

## Prerequisites

Before starting, ensure you have:

| Requirement | Details |
|-------------|---------|
| DigitalOcean account | With billing enabled |
| DO API token | Generate at [cloud.digitalocean.com/account/api/tokens](https://cloud.digitalocean.com/account/api/tokens) |
| DO Spaces access keys | Separate from API token. Generate at [cloud.digitalocean.com/account/api/spaces](https://cloud.digitalocean.com/account/api/spaces) |
| Domain name | With ability to create A records |
| SSH key pair | ed25519 recommended: `ssh-keygen -t ed25519` |
| Terraform >= 1.6.3 | [terraform.io/downloads](https://www.terraform.io/downloads) |
| SSH client | Built into macOS/Linux; PuTTY on Windows |
| SMTP credentials | For backup failure alerts (can be added post-deploy) |

**Two separate credential sets are required:**

1. **DO API Token** -- authenticates the Terraform provider (manages droplets, firewalls, volumes)
2. **DO Spaces Access Keys** -- authenticates the S3-compatible state backend and backup sync

These are different credentials. The API token cannot access Spaces, and Spaces keys cannot manage infrastructure.

## Step 1: Clone and Configure

### Clone the repository

```bash
git clone <repository-url>
cd odoo-19.x-build
```

### Configure Terraform variables

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
project_name = "odoo-prod"           # Prefix for all DO resources
region       = "nyc3"                # DO region
droplet_size = "s-2vcpu-4gb"         # 2 vCPU, 4 GB RAM ($24/mo)
volume_size_gb = 25                  # Block Storage for data + backups

# SSH: Option A -- use an existing key in your DO account
use_existing_ssh_key = true
ssh_key_name         = "my-deploy-key"

# SSH: Option B -- upload a local public key
# use_existing_ssh_key = false
# ssh_public_key_path  = "~/.ssh/id_ed25519.pub"

ssh_private_key_path = "~/.ssh/id_ed25519"
ssh_port             = 9292
allowed_ssh_ips      = ["YOUR.PUBLIC.IP/32"]  # Restrict to your IP
```

**Important:** Set `allowed_ssh_ips` to your actual public IP with a `/32` mask. Using `0.0.0.0/0` allows SSH from anywhere and is not recommended for production.

### Configure application secrets

```bash
cd ../config
cp .env.example .env
chmod 600 .env
```

Edit `.env` with strong, unique passwords:

```bash
POSTGRES_USER=odoo
POSTGRES_PASSWORD=<generate-strong-password>
POSTGRES_DB=odoo
ODOO_ADMIN_PASSWORD=<generate-different-strong-password>
```

**Password rules:**
- Do NOT use `$` (triggers variable interpolation) or backticks
- Do NOT wrap values in quotes (quotes are treated as literal characters)
- Safe special chars: `! ^ * % & # @`

Generate strong passwords with:

```bash
openssl rand -base64 32 | tr -d '/+=$'
```

## Step 2: Provision Infrastructure (Terraform)

### Set environment variables

Export the three required secrets. These are never stored in files:

```bash
export DIGITALOCEAN_TOKEN="your-do-api-token"
export AWS_ACCESS_KEY_ID="your-spaces-access-key"
export AWS_SECRET_ACCESS_KEY="your-spaces-secret-key"
```

The `AWS_*` variables are misleading names -- they authenticate DO Spaces (S3-compatible), not AWS.

### Create the Spaces bucket for Terraform state

Before `terraform init`, the state bucket must exist. Create it manually:

1. Go to [cloud.digitalocean.com/spaces](https://cloud.digitalocean.com/spaces)
2. Create a new Space named `odoo-prod-tfstate` in the `nyc3` region
3. Choose **Standard** storage tier
4. Set access to **Restrict File Listing**

Also create the backup bucket:

1. Create a new Space named `odoo-prod-backups` in the `nyc3` region
2. Choose **Cold Storage** tier (3x cheaper, suitable for infrequently accessed backups)
3. Set access to **Restrict File Listing**
4. **Configure a 30-day lifecycle expiration rule** to automatically delete old backups

   Without this rule, `rclone copy` accumulates backups indefinitely on Spaces. On Cold Storage every object incurs a minimum 30-day storage charge regardless, so expiring at 30 days is the cost-optimal retention window.

   **Method A -- DO Console:**
   - Open the `odoo-prod-backups` Space in the DigitalOcean control panel
   - Go to **Settings** > **Lifecycle Rules**
   - Add a rule: Prefix = *(leave blank for all objects)*, Expiration = **30 days**
   - Save

   **Method B -- awscli (S3-compatible):**

   Create a file called `lifecycle.json`:

   ```json
   {
     "Rules": [
       {
         "ID": "expire-backups-30d",
         "Status": "Enabled",
         "Filter": { "Prefix": "" },
         "Expiration": { "Days": 30 }
       }
     ]
   }
   ```

   Apply it:

   ```bash
   aws s3api put-bucket-lifecycle-configuration \
     --endpoint-url https://nyc3.digitaloceanspaces.com \
     --bucket odoo-prod-backups \
     --lifecycle-configuration file://lifecycle.json
   ```

   Verify the rule is active:

   ```bash
   aws s3api get-bucket-lifecycle-configuration \
     --endpoint-url https://nyc3.digitaloceanspaces.com \
     --bucket odoo-prod-backups
   ```

   Expected output should show the `expire-backups-30d` rule with `"Days": 30`.

### Initialize and apply Terraform

```bash
cd infra
terraform init
terraform plan
```

Review the plan output carefully. It should create:
- 1 VPC
- 1 Block Storage Volume (25 GB)
- 1 Droplet (s-2vcpu-4gb, Ubuntu 24.04)
- 1 Volume Attachment
- 1 Cloud Firewall
- 1 SSH key (if uploading new)

Apply when satisfied:

```bash
terraform apply
```

Type `yes` to confirm. Note the outputs:

```
droplet_ip       = "xxx.xxx.xxx.xxx"
volume_mount_path = "/mnt/odoo-prod-data"
spaces_endpoint   = "https://nyc3.digitaloceanspaces.com"
```

### Set up DNS

Create an A record pointing your domain to the droplet IP:

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | `@` or `odoo` | `<droplet_ip>` | 300 |

Wait for DNS propagation before running the SSL setup script (Step 7). You can check with:

```bash
dig +short yourdomain.com
```

## Step 3: Copy Files to Droplet

From your local machine, copy the deployment files:

```bash
scp -r config/ scripts/ root@<droplet-ip>:/tmp/odoo-setup/
```

Then copy the `.env` file with real secrets (not committed to git):

```bash
scp config/.env root@<droplet-ip>:/tmp/odoo-setup/config/
```

## Step 4: Harden Host (Script 01)

SSH into the droplet as root (last time you will use root):

```bash
ssh root@<droplet-ip>
```

Run the hardening script:

```bash
bash /tmp/odoo-setup/scripts/01-harden-host.sh
```

This script performs:
- **HARD-01:** SSH hardened (port 9292, key-only, root login disabled)
- **HARD-02:** `deploy` user created with sudo and your SSH keys
- **HARD-03:** fail2ban installed and configured (SSH + Odoo jails)
- **HARD-04:** Kernel hardening via sysctl (SYN cookies, anti-spoofing, etc.)
- **HARD-05:** UFW configured (ports 80, 443, 9292 only)
- **HARD-06:** Automatic security updates enabled (unattended-upgrades)
- **HARD-07:** auditd configured for PCI-DSS 10.x compliance

**After this script completes, root SSH is disabled.** Disconnect and reconnect:

```bash
# Exit the root session
exit

# Reconnect as deploy user on the new SSH port
ssh -p 9292 deploy@<droplet-ip>
```

If you cannot connect, verify:
- Using port 9292 (not 22)
- Using the `deploy` username (not root)
- Your SSH key is being offered
- Your IP is in the `allowed_ssh_ips` Terraform variable

## Step 5: Install Docker (Script 02)

```bash
sudo bash /tmp/odoo-setup/scripts/02-install-docker.sh
```

This script performs:
- **DOCK-01:** Installs Docker CE from the official `download.docker.com` repository (not Ubuntu's `docker.io` package)
- **DOCK-02:** Installs Docker Compose v2 plugin
- **DOCK-07:** Deploys daemon.json with `iptables: false` and log rotation

Verify Docker is running:

```bash
docker --version
docker compose version
sudo systemctl status docker
```

## Step 6: Deploy Stack (Script 03)

```bash
sudo bash /tmp/odoo-setup/scripts/03-deploy-stack.sh
```

This script performs:
- **DOCK-03/04/05:** Creates Docker networks (frontend + backend), sets up directory structure
- **DOCK-06:** Deploys docker-compose.yml, odoo.conf, postgresql.conf to `/opt/odoo/`
- **ODOO-01 through ODOO-05:** Configures Odoo (workers, memory, proxy mode, database settings)
- **PG-01 through PG-04:** Configures PostgreSQL (connection limits, memory, logging)
- Injects real passwords from `.env` into `odoo.conf` (replacing placeholders)
- Initializes CRM and Project modules

Verify containers are running:

```bash
docker compose -f /opt/odoo/docker-compose.yml ps
```

Expected output: both `odoo-app` and `odoo-db` containers with status `Up (healthy)`.

Check Odoo is responding locally:

```bash
curl -fsS http://localhost:8069/web/health
```

## Step 7: Setup Nginx + SSL (Script 04)

Ensure your DNS A record is resolving to the droplet IP before proceeding. Certbot will fail if DNS is not propagated.

```bash
sudo bash /tmp/odoo-setup/scripts/04-setup-nginx.sh yourdomain.com admin@youremail.com
```

Arguments:
- First argument: your domain name (must match DNS A record)
- Second argument: email for Let's Encrypt certificate expiry notifications

This script performs:
- **PROXY-01:** Installs Nginx, deploys pre-SSL config for certbot challenge
- **PROXY-02:** Runs certbot to obtain Let's Encrypt certificate
- **PROXY-03:** Deploys full SSL config with HSTS, security headers, gzip
- **PROXY-04:** Blocks `/web/database/*` routes (returns 403)
- **PROXY-05:** Sets up certbot renewal timer

Verify HTTPS is working:

```bash
curl -I https://yourdomain.com
```

Expected: HTTP/2 200 with `Strict-Transport-Security` header.

## Step 8: Setup Backups (Script 05)

```bash
sudo bash /tmp/odoo-setup/scripts/05-setup-backups.sh
```

This script performs:
- **BACK-01:** Installs rclone, msmtp, creates backup directory structure
- **BACK-02:** Deploys rclone config for DO Spaces sync
- **BACK-03:** Sets up cron jobs (daily backup at 2:30 AM, offsite sync at 3:30 AM)
- **BACK-04:** Sets file permissions (chmod 600 on configs with credentials)

Verify the installation:

```bash
# Check cron is installed
sudo cat /etc/cron.d/odoo-backup

# Run a test backup
sudo /opt/odoo/scripts/06-backup-daily.sh

# Check backup status
cat /opt/odoo/backup-status.json

# List the backup
ls -la /mnt/odoo-prod-data/backups/daily/
```

## Step 9: Verify Deployment

### Browser verification

1. Navigate to `https://yourdomain.com`
2. Log in with the admin credentials (the `ODOO_ADMIN_PASSWORD` from `.env`)
3. Verify the CRM module is accessible (main menu -> CRM)
4. Verify the Project module is accessible (main menu -> Project)
5. Create a test CRM lead and a test project task, then delete them

### Technical verification

```bash
# SSL certificate details
sudo certbot certificates

# Container health
docker compose -f /opt/odoo/docker-compose.yml ps

# Disk usage
df -h /mnt/odoo-prod-data/

# UFW status
sudo ufw status verbose

# fail2ban status
sudo fail2ban-client status

# Backup verification (non-destructive)
sudo bash /opt/odoo/scripts/08-restore-backup.sh --verify-only
```

### Security verification

```bash
# Verify root login is disabled
ssh root@<droplet-ip>  # Should be rejected

# Verify port 22 is closed
# (from another machine or after the cloud firewall is updated)
nc -zv <droplet-ip> 22  # Should time out

# Verify database manager is blocked
curl -I https://yourdomain.com/web/database/manager
# Should return 403
```

## Troubleshooting

### Terraform apply fails

| Error | Cause | Fix |
|-------|-------|-----|
| "Unable to authenticate" | Invalid `DIGITALOCEAN_TOKEN` | Regenerate token at DO API panel |
| "Error configuring S3 Backend" | Invalid Spaces keys or bucket doesn't exist | Verify `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` and create the bucket manually |
| "ssh_key_name not found" | SSH key doesn't exist in DO account | Upload key via DO console or set `use_existing_ssh_key = false` |
| "IP address already in use" | Previous droplet with same name | Destroy old resources or change `project_name` |

### SSH connection refused after hardening

| Symptom | Cause | Fix |
|---------|-------|-----|
| Connection refused on port 22 | SSH moved to port 9292 | Use `ssh -p 9292 deploy@<ip>` |
| Connection refused on port 9292 | Firewall blocking your IP | Check `allowed_ssh_ips` in tfvars, run `terraform apply` |
| Permission denied (publickey) | Wrong key or user | Use `deploy` user, verify your key is offered: `ssh -v -p 9292 deploy@<ip>` |
| Connection timed out | Cloud firewall misconfigured | Check DO Cloud Firewall rules in the web console |

**Emergency access:** If locked out, use the DigitalOcean web console (Droplets -> your droplet -> Console) to access the machine directly and fix firewall/SSH settings.

### Certbot fails

| Error | Cause | Fix |
|-------|-------|-----|
| "DNS problem: NXDOMAIN" | DNS not propagated | Wait and retry, or check A record |
| "too many requests" | Let's Encrypt rate limit | Wait 1 hour, use `--staging` to test first |
| "Could not bind to port 80" | Nginx not running or port conflict | `sudo systemctl status nginx`, check port 80 |
| "unauthorized" | Wrong domain or firewall blocking port 80 | Verify port 80 is open in cloud firewall and UFW |

### Containers not starting

```bash
# Check container logs
docker logs odoo-db
docker logs odoo-app

# Common issues:
# - .env file missing or wrong permissions -> chmod 600 /opt/odoo/.env
# - Disk full -> df -h /mnt/odoo-prod-data/
# - Port conflict -> sudo ss -tlnp | grep -E '8069|8072'
```

### Odoo shows 502 Bad Gateway

```bash
# Check if Odoo is running
docker compose -f /opt/odoo/docker-compose.yml ps

# Check if Odoo is bound to the right interface
curl http://127.0.0.1:8069/web/health

# Check Nginx config
sudo nginx -t
sudo systemctl status nginx

# Check Nginx error log
sudo tail -20 /var/log/nginx/odoo-error.log
```

The most common cause is running the Nginx script before the Odoo container is fully healthy. Wait for `docker compose ps` to show both containers as `Up (healthy)`.

---

*Requirement coverage: DOC-02*
*Last updated: 2026-03-17*
