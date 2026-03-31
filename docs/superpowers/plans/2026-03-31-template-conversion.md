# Template Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the Loodon-specific Odoo 19.x deployment into a reusable GitHub template with interactive setup, single-config-driven generation, and full cleanup of instance-specific artifacts.

**Architecture:** A single `instance.conf` file defines an entire deployment. `setup.sh` interactively populates it, `generate.sh` reads it and produces all instance-specific configs via heredocs. `.example` files serve as documentation with sensible demo defaults. Generated files are gitignored.

**Tech Stack:** Bash (setup.sh, generate.sh), Make, Terraform (DigitalOcean provider), Docker Compose, Nginx

**Spec:** `docs/superpowers/specs/2026-03-31-template-conversion-design.md`

---

## Task 1: Clean Up Loodon-Specific Artifacts

**Files:**
- Delete: `.planning/` (entire directory)
- Delete: `artifacts/` (entire directory)
- Delete: `HANDOFF.md`
- Delete: `odookit/` (entire directory)
- Delete: `docs/PRD.md`
- Delete: `docs/ubop-foundation-setup.md`
- Delete: `docs/portal-domain-setup.md`
- Delete: `docs/index.md`
- Delete: `docs/superpowers/plans/` (all existing plans except the new ones)
- Delete: `mkdocs.yml`

- [ ] **Step 1: Remove planning artifacts and Loodon-specific docs**

```bash
rm -rf .planning/
rm -rf artifacts/
rm -f HANDOFF.md
rm -f docs/PRD.md
rm -f docs/ubop-foundation-setup.md
rm -f docs/portal-domain-setup.md
rm -f docs/index.md
rm -f mkdocs.yml
```

- [ ] **Step 2: Remove OdooKit directory**

```bash
rm -rf odookit/
```

- [ ] **Step 3: Remove old superpowers plans (keep specs and the new plan)**

```bash
# Remove the old Loodon build plans
rm -f docs/superpowers/plans/2026-03-26-ubop-foundation-setup.md
# Keep: docs/superpowers/specs/2026-03-31-template-conversion-design.md
# Keep: docs/superpowers/plans/2026-03-31-template-conversion.md (this plan)
```

Verify no other plan files exist:

```bash
ls docs/superpowers/plans/
```

Expected: only `2026-03-31-template-conversion.md`

- [ ] **Step 4: Verify cleanup**

```bash
# These should all return "No such file or directory"
ls .planning/ 2>&1
ls artifacts/ 2>&1
ls HANDOFF.md 2>&1
ls odookit/ 2>&1
ls docs/PRD.md 2>&1
ls mkdocs.yml 2>&1
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove Loodon-specific artifacts and planning history

Remove .planning/, artifacts/, HANDOFF.md, odookit/, Loodon-specific
docs, mkdocs.yml, and old build plans. Clean slate for template."
```

---

## Task 2: Create `instance.conf.example`

**Files:**
- Create: `instance.conf.example`

- [ ] **Step 1: Create instance.conf.example**

```bash
cat > instance.conf.example << 'CONF'
# =============================================================================
# Instance Configuration — Odoo Droplet Template
# =============================================================================
# This file defines all instance-specific values for a deployment.
# Copy to instance.conf and customize, or run `make init` for interactive setup.
#
# Defaults below produce a working demo/dev instance.
# =============================================================================

# --- Project Identity ---
PROJECT_NAME="odoo-demo"
ORGANIZATION="Acme Corp"

# --- Domain Configuration ---
DOMAIN_MODE="single"              # "single" or "multi"
PRIMARY_DOMAIN="odoo.example.com"
ALIAS_DOMAINS=""                  # Comma-separated, only used if DOMAIN_MODE=multi
ADMIN_EMAIL="admin@example.com"   # Let's Encrypt + Odoo admin notifications

# --- DigitalOcean Infrastructure ---
DO_REGION="nyc3"
DROPLET_SIZE="s-2vcpu-4gb"
VOLUME_SIZE_GB="25"
SSH_KEY_FINGERPRINT=""            # Leave blank to upload ~/.ssh/id_ed25519.pub
SSH_PORT="9292"

# --- Database ---
DB_NAME="odoo-01"
DB_USER="odoo"

# --- Spaces (Object Storage) ---
TFSTATE_BUCKET="${PROJECT_NAME}-tfstate"
BACKUP_BUCKET="${PROJECT_NAME}-backups"
SPACES_REGION="${DO_REGION}"

# --- Backup ---
BACKUP_RETENTION_DAYS="30"
BACKUP_NOTIFY_EMAIL="${ADMIN_EMAIL}"

# --- Monitoring (optional) ---
ICINGA2_ENABLED="false"
ICINGA2_MASTER=""                 # Hostname of Icinga2 master

# --- OdooKit (optional) ---
ODOOKIT_REPO="https://github.com/salsedge/odookit"
CONF
```

- [ ] **Step 2: Verify file is valid bash**

```bash
bash -n instance.conf.example
```

Expected: no output (clean parse)

- [ ] **Step 3: Commit**

```bash
git add instance.conf.example
git commit -m "feat: add instance.conf.example as template configuration reference"
```

---

## Task 3: Update `.gitignore` for Generated Files

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Read current .gitignore**

```bash
cat .gitignore
```

- [ ] **Step 2: Replace .gitignore with updated version**

Replace the full contents of `.gitignore` with:

```gitignore
.DS_Store
.obsidian/
.z_notes/

# Local .terraform directories
.terraform/

# .tfstate files
*.tfstate
*.tfstate.*

# Crash log files
crash.log
crash.*.log

# Exclude all .tfvars files (sensitive data)
*.tfvars
*.tfvars.json

# Ignore override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Ignore transient lock info files
.terraform.tfstate.lock.info

# Ignore CLI configuration files
.terraformrc
terraform.rc

# Environment files with secrets
.env
config/.env

# Instance-specific (generated by generate.sh)
instance.conf
infra/backend.tf
config/odoo.conf
config/nginx/odoo-pre-ssl.conf
config/nginx/odoo.conf
config/rclone.conf
config/msmtprc
monitoring/icinga2/commands.conf

# OdooKit (cloned separately)
odookit/

# MkDocs build output
site/
```

- [ ] **Step 3: Verify no tracked files are now ignored**

```bash
git status
```

Expect: `.gitignore` shows as modified. `infra/backend.tf`, `config/odoo.conf`, etc. should show as deleted from tracking (they'll be removed in the next tasks when renamed to `.example`).

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: update .gitignore for template — ignore generated configs and instance.conf"
```

---

## Task 4: Convert Config Files to `.example` Pattern

**Files:**
- Rename: `infra/backend.tf` → `infra/backend.tf.example`
- Rename: `config/odoo.conf` → `config/odoo.conf.example`
- Rename: `config/nginx/odoo.conf` → `config/nginx/odoo-single.conf.example`
- Rename: `config/nginx/odoo-pre-ssl.conf` → `config/nginx/odoo-pre-ssl.conf.example`
- Keep as-is: `config/nginx/odoo-multidomain.conf` → rename to `config/nginx/odoo-multi.conf.example`
- Modify: `config/docker-compose.yml` (replace hardcoded mount path)
- Rename: `config/rclone.conf.example` (already .example, keep)
- Rename: `config/msmtprc.example` (already .example, keep)

- [ ] **Step 1: Rename backend.tf to .example and generalize**

```bash
git mv infra/backend.tf infra/backend.tf.example
```

Edit `infra/backend.tf.example` — replace the hardcoded bucket and endpoint:
- Line 24: change `s3 = "https://nyc3.digitaloceanspaces.com"` to `s3 = "https://SPACES_REGION.digitaloceanspaces.com"`
- Line 27: change `bucket = "odoo-prod-tfstate"` to `bucket = "TFSTATE_BUCKET_NAME"`

The file comment header should note: `# EXAMPLE ONLY — generated by: make generate`

- [ ] **Step 2: Rename odoo.conf to .example**

```bash
git mv config/odoo.conf config/odoo.conf.example
```

No content changes needed — it already uses `DB_USER_PLACEHOLDER`, `DB_PASSWORD_PLACEHOLDER`, `DB_NAME_PLACEHOLDER`, `ADMIN_PASSWORD_PLACEHOLDER` tokens.

Add a comment at the top: `; EXAMPLE ONLY — generated by: make generate`

- [ ] **Step 3: Rename and reorganize Nginx configs**

```bash
git mv config/nginx/odoo.conf config/nginx/odoo-single.conf.example
git mv config/nginx/odoo-pre-ssl.conf config/nginx/odoo-pre-ssl.conf.example
git mv config/nginx/odoo-multidomain.conf config/nginx/odoo-multi.conf.example
```

Add comment to each: `# EXAMPLE ONLY — generated by: make generate`

- [ ] **Step 4: Generalize docker-compose.yml volume mount path**

Edit `config/docker-compose.yml`:
- Line 10: change comment from `at /mnt/odoo-prod-data/` to `on Block Storage Volume`
- Line 29: change `/mnt/odoo-prod-data/postgres-data` to `/mnt/${PROJECT_NAME}-data/postgres-data`
- Line 77: change `/mnt/odoo-prod-data/odoo-filestore` to `/mnt/${PROJECT_NAME}-data/odoo-filestore`

**Important:** These `${PROJECT_NAME}` references will be resolved at deploy time by the deploy script, not by Docker Compose. The deploy script (`03-deploy-stack.sh`) already uses a `VOLUME_MOUNT` variable — this change makes the compose file's comments match.

Actually, re-reading the deploy script: `03-deploy-stack.sh` copies `docker-compose.yml` to `/opt/odoo/` and the volume paths are used as-is by Docker. So these need to stay as literal paths that match the actual mount point.

Better approach: keep `docker-compose.yml` with a placeholder path and have `generate.sh` produce it. But `docker-compose.yml` is currently listed as "static" in the spec because it uses env vars for credentials. The volume mount paths are the one exception.

Resolution: Add `config/docker-compose.yml` to the generated files list. `generate.sh` will read `config/docker-compose.yml.example` and substitute the volume mount path.

```bash
git mv config/docker-compose.yml config/docker-compose.yml.example
```

Edit `config/docker-compose.yml.example`:
- Line 10: change `at /mnt/odoo-prod-data/` to `at VOLUME_MOUNT_PLACEHOLDER`
- Line 29: change `/mnt/odoo-prod-data/postgres-data` to `VOLUME_MOUNT_PLACEHOLDER/postgres-data`
- Line 77: change `/mnt/odoo-prod-data/odoo-filestore` to `VOLUME_MOUNT_PLACEHOLDER/odoo-filestore`

Add comment at top (after existing header): `# EXAMPLE ONLY — generated by: make generate`

- [ ] **Step 5: Verify all renames succeeded**

```bash
ls infra/backend.tf.example
ls config/odoo.conf.example
ls config/docker-compose.yml.example
ls config/nginx/odoo-single.conf.example
ls config/nginx/odoo-pre-ssl.conf.example
ls config/nginx/odoo-multi.conf.example
ls config/rclone.conf.example
ls config/msmtprc.example
```

All should exist. The non-`.example` versions should not exist:

```bash
ls infra/backend.tf config/odoo.conf config/docker-compose.yml config/nginx/odoo.conf config/nginx/odoo-pre-ssl.conf 2>&1
```

Expected: all "No such file or directory"

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename instance-specific configs to .example pattern

backend.tf, odoo.conf, docker-compose.yml, and nginx configs renamed
to .example extensions. generate.sh will produce the actual configs
from instance.conf values. Placeholder tokens added for mount paths
and bucket names."
```

---

## Task 5: Generalize Hardcoded Paths in Scripts

**Files:**
- Modify: `scripts/03-deploy-stack.sh` (line ~27)
- Modify: `scripts/05-setup-backups.sh` (line ~25)
- Modify: `scripts/06-backup-daily.sh` (lines ~26-27)
- Modify: `scripts/07-sync-offsite.sh` (line ~25, ~108)
- Modify: `scripts/08-restore-backup.sh` (lines ~28, ~197)

All scripts currently hardcode `VOLUME_MOUNT="/mnt/odoo-prod-data"`. These need to read the mount path from an environment variable or derive it from the project name.

- [ ] **Step 1: Read each script's VOLUME_MOUNT line**

```bash
grep -n 'VOLUME_MOUNT\|odoo-prod-data\|odoo-prod-backups' scripts/*.sh
```

- [ ] **Step 2: Update scripts/03-deploy-stack.sh**

Change the `VOLUME_MOUNT` assignment (around line 27) from:

```bash
VOLUME_MOUNT="/mnt/odoo-prod-data"
```

to:

```bash
VOLUME_MOUNT="${VOLUME_MOUNT:-/mnt/odoo-prod-data}"
```

This lets the value be overridden by environment but keeps the current default for backward compatibility. The deploy Makefile target will export the correct value from `instance.conf`.

- [ ] **Step 3: Update scripts/05-setup-backups.sh**

Same pattern — change `VOLUME_MOUNT` assignment (around line 25) from:

```bash
VOLUME_MOUNT="/mnt/odoo-prod-data"
```

to:

```bash
VOLUME_MOUNT="${VOLUME_MOUNT:-/mnt/odoo-prod-data}"
```

Also check for hardcoded `spaces:odoo-prod-backups` references (around lines 179-182) and change to use a variable:

```bash
RCLONE_REMOTE="${RCLONE_REMOTE:-spaces:odoo-prod-backups}"
```

Replace any literal `spaces:odoo-prod-backups` with `${RCLONE_REMOTE}`.

- [ ] **Step 4: Update scripts/06-backup-daily.sh**

Change hardcoded paths (around lines 26-27) from:

```bash
BACKUP_DIR="/mnt/odoo-prod-data/backups"
FILESTORE_DIR="/mnt/odoo-prod-data/odoo-filestore"
```

to:

```bash
VOLUME_MOUNT="${VOLUME_MOUNT:-/mnt/odoo-prod-data}"
BACKUP_DIR="${VOLUME_MOUNT}/backups"
FILESTORE_DIR="${VOLUME_MOUNT}/odoo-filestore"
```

- [ ] **Step 5: Update scripts/07-sync-offsite.sh**

Change hardcoded path (around line 25) from:

```bash
BACKUP_DIR="/mnt/odoo-prod-data/backups/daily"
```

to:

```bash
VOLUME_MOUNT="${VOLUME_MOUNT:-/mnt/odoo-prod-data}"
BACKUP_DIR="${VOLUME_MOUNT}/backups/daily"
```

Also check for hardcoded `spaces:odoo-prod-backups` (around line 108) and replace with:

```bash
RCLONE_REMOTE="${RCLONE_REMOTE:-spaces:odoo-prod-backups}"
```

- [ ] **Step 6: Update scripts/08-restore-backup.sh**

Change hardcoded path (around line 28) from:

```bash
BACKUP_DIR="/mnt/odoo-prod-data/backups"
```

to:

```bash
VOLUME_MOUNT="${VOLUME_MOUNT:-/mnt/odoo-prod-data}"
BACKUP_DIR="${VOLUME_MOUNT}/backups"
```

Also check for hardcoded `spaces:odoo-prod-backups` references and replace with `${RCLONE_REMOTE}`.

- [ ] **Step 7: Verify no hardcoded odoo-prod-data or odoo-prod-backups remain**

```bash
grep -rn 'odoo-prod-data\|odoo-prod-backups' scripts/
```

Expected: no matches (only `${VOLUME_MOUNT}` and `${RCLONE_REMOTE}` references)

- [ ] **Step 8: Run shellcheck on modified scripts**

```bash
shellcheck scripts/03-deploy-stack.sh scripts/05-setup-backups.sh scripts/06-backup-daily.sh scripts/07-sync-offsite.sh scripts/08-restore-backup.sh
```

Expected: no new errors

- [ ] **Step 9: Commit**

```bash
git add scripts/03-deploy-stack.sh scripts/05-setup-backups.sh scripts/06-backup-daily.sh scripts/07-sync-offsite.sh scripts/08-restore-backup.sh
git commit -m "refactor: parameterize volume mount and rclone remote in deploy scripts

Replace hardcoded /mnt/odoo-prod-data and spaces:odoo-prod-backups
with environment variables that default to the original values.
generate.sh will set the correct values per instance."
```

---

## Task 6: Generalize Monitoring and BookStack Config

**Files:**
- Modify: `monitoring/icinga2/commands.conf` (lines ~106-107)
- Modify: `.bookstack/defaults.env`

- [ ] **Step 1: Read monitoring commands.conf**

```bash
grep -n 'loomin\|loodon' monitoring/icinga2/commands.conf
```

- [ ] **Step 2: Replace Loodon-specific defaults in commands.conf**

Change any `loomin` references to `DB_USER_PLACEHOLDER` and `loodon-01` to `DB_NAME_PLACEHOLDER`. These will be substituted by `generate.sh` when `ICINGA2_ENABLED=true`.

Since monitoring configs are generated, rename to `.example`:

```bash
git mv monitoring/icinga2/commands.conf monitoring/icinga2/commands.conf.example
```

Edit the file to replace Loodon-specific values with placeholders.

- [ ] **Step 3: Update .bookstack/defaults.env**

```bash
cat .bookstack/defaults.env
```

Change `BOOKSTACK_DEFAULT_INSTANCE=BIBBEO` to `BOOKSTACK_DEFAULT_INSTANCE=` (empty, to be configured per instance).

- [ ] **Step 4: Commit**

```bash
git add monitoring/ .bookstack/
git commit -m "refactor: generalize monitoring and BookStack config

Replace Loodon-specific DB defaults in Icinga2 commands with
placeholders. Clear BookStack instance default."
```

---

## Task 7: Create `generate.sh`

**Files:**
- Create: `generate.sh`

- [ ] **Step 1: Create generate.sh**

Create `generate.sh` at the project root. This is the core config generation engine. It reads `instance.conf` and produces all generated files.

```bash
#!/usr/bin/env bash
# =============================================================================
# generate.sh — Produce instance-specific configs from instance.conf
# =============================================================================
# Reads instance.conf and generates all config files using heredocs.
# Re-runnable: change a value in instance.conf, run again. Preserves
# existing passwords in config/.env.
#
# Usage: ./generate.sh [--force]
#   --force  Overwrite config/.env passwords (default: preserve existing)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE_CONF="${SCRIPT_DIR}/instance.conf"

# --- Pre-flight checks ---
if [[ ! -f "$INSTANCE_CONF" ]]; then
  echo "ERROR: instance.conf not found. Run 'make init' first." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$INSTANCE_CONF"

# --- Resolve cascading defaults ---
PROJECT_NAME="${PROJECT_NAME:?PROJECT_NAME is required}"
ORGANIZATION="${ORGANIZATION:-$PROJECT_NAME}"
PRIMARY_DOMAIN="${PRIMARY_DOMAIN:?PRIMARY_DOMAIN is required}"
ADMIN_EMAIL="${ADMIN_EMAIL:?ADMIN_EMAIL is required}"
DO_REGION="${DO_REGION:-nyc3}"
DROPLET_SIZE="${DROPLET_SIZE:-s-2vcpu-4gb}"
VOLUME_SIZE_GB="${VOLUME_SIZE_GB:-25}"
SSH_KEY_FINGERPRINT="${SSH_KEY_FINGERPRINT:-}"
SSH_PORT="${SSH_PORT:-9292}"
DB_NAME="${DB_NAME:-odoo-01}"
DB_USER="${DB_USER:-odoo}"
TFSTATE_BUCKET="${TFSTATE_BUCKET:-${PROJECT_NAME}-tfstate}"
BACKUP_BUCKET="${BACKUP_BUCKET:-${PROJECT_NAME}-backups}"
SPACES_REGION="${SPACES_REGION:-$DO_REGION}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_NOTIFY_EMAIL="${BACKUP_NOTIFY_EMAIL:-$ADMIN_EMAIL}"
ICINGA2_ENABLED="${ICINGA2_ENABLED:-false}"
ICINGA2_MASTER="${ICINGA2_MASTER:-}"
DOMAIN_MODE="${DOMAIN_MODE:-single}"
ALIAS_DOMAINS="${ALIAS_DOMAINS:-}"

VOLUME_MOUNT="/mnt/${PROJECT_NAME}-data"
RCLONE_REMOTE="spaces:${BACKUP_BUCKET}"

FORCE_OVERWRITE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE_OVERWRITE=true
fi

GENERATED_HEADER="# Generated from instance.conf — do not edit directly. Re-run: make generate"

echo "Generating configs for: ${PROJECT_NAME} (${PRIMARY_DOMAIN})..."

# --- infra/backend.tf ---
cat > "${SCRIPT_DIR}/infra/backend.tf" << EOF
${GENERATED_HEADER}

terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://${SPACES_REGION}.digitaloceanspaces.com"
    }

    bucket = "${TFSTATE_BUCKET}"
    key    = "terraform.tfstate"

    # Required by S3 backend but unused by DigitalOcean
    region = "us-east-1"

    # Required flags for non-AWS S3-compatible backends
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
EOF
echo "  → infra/backend.tf"

# --- infra/terraform.tfvars ---
cat > "${SCRIPT_DIR}/infra/terraform.tfvars" << EOF
${GENERATED_HEADER}

project_name = "${PROJECT_NAME}"
region       = "${DO_REGION}"
droplet_size = "${DROPLET_SIZE}"
volume_size_gb = ${VOLUME_SIZE_GB}
ssh_port     = ${SSH_PORT}
EOF

if [[ -n "$SSH_KEY_FINGERPRINT" ]]; then
  cat >> "${SCRIPT_DIR}/infra/terraform.tfvars" << EOF
use_existing_ssh_key = true
ssh_key_name         = "${PROJECT_NAME}-deploy-key"
EOF
else
  cat >> "${SCRIPT_DIR}/infra/terraform.tfvars" << EOF
use_existing_ssh_key = false
ssh_public_key_path  = "~/.ssh/id_ed25519.pub"
ssh_private_key_path = "~/.ssh/id_ed25519"
EOF
fi
echo "  → infra/terraform.tfvars"

# --- config/.env ---
ENV_FILE="${SCRIPT_DIR}/config/.env"

# Generate random passwords (or preserve existing)
if [[ -f "$ENV_FILE" ]] && [[ "$FORCE_OVERWRITE" == "false" ]]; then
  # Preserve existing passwords
  EXISTING_PG_PASS=$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)
  EXISTING_ADMIN_PASS=$(grep '^ODOO_ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)
  PG_PASSWORD="${EXISTING_PG_PASS:-$(openssl rand -base64 24)}"
  ADMIN_PASSWORD="${EXISTING_ADMIN_PASS:-$(openssl rand -base64 24)}"
  echo "  → config/.env (preserving existing passwords)"
else
  PG_PASSWORD="$(openssl rand -base64 24)"
  ADMIN_PASSWORD="$(openssl rand -base64 24)"
  echo "  → config/.env (new passwords generated)"
fi

cat > "$ENV_FILE" << EOF
${GENERATED_HEADER}

# Database credentials
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${PG_PASSWORD}
POSTGRES_DB=${DB_NAME}

# Odoo admin master password
ODOO_ADMIN_PASSWORD=${ADMIN_PASSWORD}

# DigitalOcean Spaces (for backups)
SPACES_ACCESS_KEY=your_spaces_access_key
SPACES_SECRET_KEY=your_spaces_secret_key
SPACES_REGION=${SPACES_REGION}

# SMTP (for backup failure notifications)
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_FROM=alerts@${PRIMARY_DOMAIN}
SMTP_USER=smtp_username
SMTP_PASSWORD=smtp_password
ALERT_EMAIL=${BACKUP_NOTIFY_EMAIL}
EOF

chmod 600 "$ENV_FILE"

# --- config/odoo.conf ---
cat > "${SCRIPT_DIR}/config/odoo.conf" << 'ODOO_CONF_HEADER'
; Generated from instance.conf — do not edit directly. Re-run: make generate
ODOO_CONF_HEADER

# Read the example and substitute placeholders
sed \
  -e "s/DB_USER_PLACEHOLDER/${DB_USER}/g" \
  -e "s/DB_PASSWORD_PLACEHOLDER/\${POSTGRES_PASSWORD}/g" \
  -e "s/DB_NAME_PLACEHOLDER/${DB_NAME}/g" \
  -e "s/ADMIN_PASSWORD_PLACEHOLDER/\${ODOO_ADMIN_PASSWORD}/g" \
  "${SCRIPT_DIR}/config/odoo.conf.example" \
  | grep -v '^; EXAMPLE ONLY' \
  >> "${SCRIPT_DIR}/config/odoo.conf"
echo "  → config/odoo.conf"

# --- config/docker-compose.yml ---
sed \
  -e "s|VOLUME_MOUNT_PLACEHOLDER|${VOLUME_MOUNT}|g" \
  "${SCRIPT_DIR}/config/docker-compose.yml.example" \
  | sed '1s/^/# Generated from instance.conf — do not edit directly. Re-run: make generate\n/' \
  > "${SCRIPT_DIR}/config/docker-compose.yml"
echo "  → config/docker-compose.yml"

# --- config/nginx/odoo-pre-ssl.conf ---
sed \
  -e "s/DOMAIN_PLACEHOLDER/${PRIMARY_DOMAIN}/g" \
  "${SCRIPT_DIR}/config/nginx/odoo-pre-ssl.conf.example" \
  | sed '1s/^/# Generated from instance.conf — do not edit directly. Re-run: make generate\n/' \
  > "${SCRIPT_DIR}/config/nginx/odoo-pre-ssl.conf"
echo "  → config/nginx/odoo-pre-ssl.conf"

# --- config/nginx/odoo.conf ---
if [[ "$DOMAIN_MODE" == "multi" ]] && [[ -n "$ALIAS_DOMAINS" ]]; then
  TEMPLATE="${SCRIPT_DIR}/config/nginx/odoo-multi.conf.example"
  # Build server_name line: primary + all aliases
  ALL_DOMAINS="${PRIMARY_DOMAIN}"
  IFS=',' read -ra ALIASES <<< "$ALIAS_DOMAINS"
  for alias in "${ALIASES[@]}"; do
    alias="$(echo "$alias" | xargs)"  # trim whitespace
    ALL_DOMAINS="${ALL_DOMAINS} ${alias}"
  done
  # Use the first alias as ALIAS_DOMAIN for the redirect block
  FIRST_ALIAS="$(echo "$ALIAS_DOMAINS" | cut -d, -f1 | xargs)"
  sed \
    -e "s/PRIMARY_DOMAIN/${PRIMARY_DOMAIN}/g" \
    -e "s/ALIAS_DOMAIN/${FIRST_ALIAS}/g" \
    -e "s/CERT_NAME/${PRIMARY_DOMAIN}/g" \
    "$TEMPLATE" \
    | sed '1s/^/# Generated from instance.conf — do not edit directly. Re-run: make generate\n/' \
    > "${SCRIPT_DIR}/config/nginx/odoo.conf"
else
  sed \
    -e "s/DOMAIN_PLACEHOLDER/${PRIMARY_DOMAIN}/g" \
    -e "s/CERT_NAME/${PRIMARY_DOMAIN}/g" \
    "${SCRIPT_DIR}/config/nginx/odoo-single.conf.example" \
    | sed '1s/^/# Generated from instance.conf — do not edit directly. Re-run: make generate\n/' \
    > "${SCRIPT_DIR}/config/nginx/odoo.conf"
fi
echo "  → config/nginx/odoo.conf (${DOMAIN_MODE} mode)"

# --- config/rclone.conf ---
sed \
  -e "s/SPACES_ACCESS_KEY_PLACEHOLDER/\${SPACES_ACCESS_KEY}/g" \
  -e "s/SPACES_SECRET_KEY_PLACEHOLDER/\${SPACES_SECRET_KEY}/g" \
  -e "s/SPACES_REGION_PLACEHOLDER/${SPACES_REGION}/g" \
  "${SCRIPT_DIR}/config/rclone.conf.example" \
  | sed '1s/^/# Generated from instance.conf — do not edit directly. Re-run: make generate\n/' \
  > "${SCRIPT_DIR}/config/rclone.conf"
echo "  → config/rclone.conf"

# --- config/msmtprc ---
sed \
  -e "s/SMTP_HOST_PLACEHOLDER/\${SMTP_HOST}/g" \
  -e "s/SMTP_PORT_PLACEHOLDER/\${SMTP_PORT}/g" \
  -e "s/SMTP_FROM_PLACEHOLDER/alerts@${PRIMARY_DOMAIN}/g" \
  -e "s/SMTP_USER_PLACEHOLDER/\${SMTP_USER}/g" \
  -e "s/SMTP_PASSWORD_PLACEHOLDER/\${SMTP_PASSWORD}/g" \
  "${SCRIPT_DIR}/config/msmtprc.example" \
  | sed '1s/^/# Generated from instance.conf — do not edit directly. Re-run: make generate\n/' \
  > "${SCRIPT_DIR}/config/msmtprc"
echo "  → config/msmtprc"

# --- monitoring/icinga2/commands.conf (conditional) ---
if [[ "$ICINGA2_ENABLED" == "true" ]]; then
  sed \
    -e "s/DB_USER_PLACEHOLDER/${DB_USER}/g" \
    -e "s/DB_NAME_PLACEHOLDER/${DB_NAME}/g" \
    "${SCRIPT_DIR}/monitoring/icinga2/commands.conf.example" \
    | sed '1s/^/# Generated from instance.conf — do not edit directly. Re-run: make generate\n/' \
    > "${SCRIPT_DIR}/monitoring/icinga2/commands.conf"
  echo "  → monitoring/icinga2/commands.conf"
else
  echo "  → monitoring/icinga2/commands.conf (skipped — ICINGA2_ENABLED=false)"
fi

echo ""
echo "Done. Review generated files, then:"
echo "  make tf-init    # Initialize Terraform"
echo "  make tf-apply   # Provision infrastructure"
echo "  make deploy     # Deploy to droplet"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x generate.sh
```

- [ ] **Step 3: Test with a mock instance.conf**

Create a temporary `instance.conf` for testing:

```bash
cp instance.conf.example instance.conf
sed -i '' 's/odoo-demo/test-instance/g' instance.conf
sed -i '' 's/odoo.example.com/test.example.com/g' instance.conf
```

Run the generator:

```bash
./generate.sh
```

Expected output:

```
Generating configs for: test-instance (test.example.com)...
  → infra/backend.tf
  → infra/terraform.tfvars
  → config/.env (new passwords generated)
  → config/odoo.conf
  → config/docker-compose.yml
  → config/nginx/odoo-pre-ssl.conf
  → config/nginx/odoo.conf (single mode)
  → config/rclone.conf
  → config/msmtprc
  → monitoring/icinga2/commands.conf (skipped — ICINGA2_ENABLED=false)
```

- [ ] **Step 4: Verify generated files contain correct values**

```bash
grep 'test-instance-tfstate' infra/backend.tf
grep 'test-instance' infra/terraform.tfvars
grep 'test.example.com' config/nginx/odoo-pre-ssl.conf
grep 'test.example.com' config/nginx/odoo.conf
grep '/mnt/test-instance-data' config/docker-compose.yml
```

All should return matches.

- [ ] **Step 5: Test password preservation**

```bash
FIRST_PASS=$(grep 'POSTGRES_PASSWORD' config/.env | cut -d= -f2-)
./generate.sh
SECOND_PASS=$(grep 'POSTGRES_PASSWORD' config/.env | cut -d= -f2-)
[[ "$FIRST_PASS" == "$SECOND_PASS" ]] && echo "PASS: passwords preserved" || echo "FAIL: passwords changed"
```

Expected: "PASS: passwords preserved"

- [ ] **Step 6: Test --force flag**

```bash
FIRST_PASS=$(grep 'POSTGRES_PASSWORD' config/.env | cut -d= -f2-)
./generate.sh --force
SECOND_PASS=$(grep 'POSTGRES_PASSWORD' config/.env | cut -d= -f2-)
[[ "$FIRST_PASS" != "$SECOND_PASS" ]] && echo "PASS: passwords regenerated" || echo "FAIL: passwords not changed"
```

Expected: "PASS: passwords regenerated"

- [ ] **Step 7: Clean up test files**

```bash
rm -f instance.conf
rm -f infra/backend.tf infra/terraform.tfvars
rm -f config/.env config/odoo.conf config/docker-compose.yml
rm -f config/nginx/odoo-pre-ssl.conf config/nginx/odoo.conf
rm -f config/rclone.conf config/msmtprc
rm -f monitoring/icinga2/commands.conf
```

- [ ] **Step 8: Run shellcheck**

```bash
shellcheck generate.sh
```

Fix any warnings.

- [ ] **Step 9: Commit**

```bash
git add generate.sh
git commit -m "feat: add generate.sh — produces all configs from instance.conf

Reads instance.conf and generates backend.tf, terraform.tfvars,
.env (with random passwords), odoo.conf, docker-compose.yml, nginx
configs (single or multi-domain), rclone.conf, msmtprc, and
optionally icinga2 commands.conf. Preserves existing passwords
on re-run unless --force is passed."
```

---

## Task 8: Create `setup.sh`

**Files:**
- Create: `setup.sh`

- [ ] **Step 1: Create setup.sh**

Create `setup.sh` at the project root. This is the interactive setup wizard.

```bash
#!/usr/bin/env bash
# =============================================================================
# setup.sh — Interactive instance configuration wizard
# =============================================================================
# Walks through instance.conf.example section by section, presenting defaults
# and accepting overrides. Writes instance.conf and calls generate.sh.
#
# Usage: ./setup.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_CONF="${SCRIPT_DIR}/instance.conf.example"
INSTANCE_CONF="${SCRIPT_DIR}/instance.conf"

# --- Colors ---
BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

# --- Helper functions ---
prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default="$3"
  local value

  printf "${CYAN}%s${RESET} [${GREEN}%s${RESET}]: " "$prompt_text" "$default"
  read -r value
  value="${value:-$default}"
  eval "$var_name=\"$value\""
}

prompt_choice() {
  local var_name="$1"
  local prompt_text="$2"
  local options="$3"
  local default="$4"
  local value

  printf "${CYAN}%s (%s)${RESET} [${GREEN}%s${RESET}]: " "$prompt_text" "$options" "$default"
  read -r value
  value="${value:-$default}"
  eval "$var_name=\"$value\""
}

prompt_yesno() {
  local var_name="$1"
  local prompt_text="$2"
  local default="$3"
  local value

  printf "${CYAN}%s${RESET} [${GREEN}%s${RESET}]: " "$prompt_text" "$default"
  read -r value
  value="${value:-$default}"
  if [[ "$value" =~ ^[Yy] ]]; then
    eval "$var_name=true"
  else
    eval "$var_name=false"
  fi
}

validate_domain() {
  local domain="$1"
  if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    echo "WARNING: '$domain' may not be a valid domain name" >&2
  fi
}

validate_port() {
  local port="$1"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    echo "ERROR: '$port' is not a valid port number (1-65535)" >&2
    return 1
  fi
}

validate_bucket() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
    echo "WARNING: '$name' may not be a valid bucket name (lowercase, 3-63 chars, DNS-compliant)" >&2
  fi
}

# --- Load existing instance.conf as defaults (if re-running) ---
if [[ -f "$INSTANCE_CONF" ]]; then
  echo -e "${YELLOW}Found existing instance.conf — using current values as defaults${RESET}"
  # shellcheck source=/dev/null
  source "$INSTANCE_CONF"
fi

# --- Load .example defaults for anything not already set ---
if [[ -f "$EXAMPLE_CONF" ]]; then
  while IFS='=' read -r key value; do
    key=$(echo "$key" | xargs)
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    # Only set if not already defined
    if [[ -z "${!key:-}" ]]; then
      eval "$key=\"$value\""
    fi
  done < <(grep -v '^\s*#' "$EXAMPLE_CONF" | grep '=')
fi

# --- Interactive wizard ---
echo ""
echo -e "${BOLD}=== Odoo Instance Setup ===${RESET}"
echo ""

# --- Project Identity ---
echo -e "${BOLD}--- Project Identity ---${RESET}"
prompt PROJECT_NAME "Project name" "${PROJECT_NAME:-odoo-demo}"
prompt ORGANIZATION "Organization" "${ORGANIZATION:-Acme Corp}"
echo ""

# --- Domain Configuration ---
echo -e "${BOLD}--- Domain Configuration ---${RESET}"
prompt_choice DOMAIN_MODE "Domain mode" "single/multi" "${DOMAIN_MODE:-single}"
prompt PRIMARY_DOMAIN "Primary domain" "${PRIMARY_DOMAIN:-odoo.example.com}"
validate_domain "$PRIMARY_DOMAIN"

if [[ "$DOMAIN_MODE" == "multi" ]]; then
  prompt ALIAS_DOMAINS "Alias domains (comma-separated)" "${ALIAS_DOMAINS:-}"
fi

prompt ADMIN_EMAIL "Admin email" "${ADMIN_EMAIL:-admin@example.com}"
echo ""

# --- DigitalOcean Infrastructure ---
echo -e "${BOLD}--- DigitalOcean Infrastructure ---${RESET}"
prompt DO_REGION "Region" "${DO_REGION:-nyc3}"
prompt DROPLET_SIZE "Droplet size" "${DROPLET_SIZE:-s-2vcpu-4gb}"
prompt VOLUME_SIZE_GB "Volume size (GB)" "${VOLUME_SIZE_GB:-25}"
prompt SSH_KEY_FINGERPRINT "SSH key fingerprint (blank to upload default)" "${SSH_KEY_FINGERPRINT:-}"
prompt SSH_PORT "SSH port" "${SSH_PORT:-9292}"
validate_port "$SSH_PORT"
echo ""

# --- Database ---
echo -e "${BOLD}--- Database ---${RESET}"
prompt DB_NAME "Database name" "${DB_NAME:-odoo-01}"
prompt DB_USER "Database user" "${DB_USER:-odoo}"
echo ""

# --- Spaces (Object Storage) ---
echo -e "${BOLD}--- Spaces (Object Storage) ---${RESET}"
prompt TFSTATE_BUCKET "TF state bucket" "${TFSTATE_BUCKET:-${PROJECT_NAME}-tfstate}"
validate_bucket "$TFSTATE_BUCKET"
prompt BACKUP_BUCKET "Backup bucket" "${BACKUP_BUCKET:-${PROJECT_NAME}-backups}"
validate_bucket "$BACKUP_BUCKET"
prompt SPACES_REGION "Spaces region" "${SPACES_REGION:-$DO_REGION}"
echo ""

# --- Backup ---
echo -e "${BOLD}--- Backup ---${RESET}"
prompt BACKUP_RETENTION_DAYS "Retention days" "${BACKUP_RETENTION_DAYS:-30}"
prompt BACKUP_NOTIFY_EMAIL "Notification email" "${BACKUP_NOTIFY_EMAIL:-$ADMIN_EMAIL}"
echo ""

# --- Monitoring ---
echo -e "${BOLD}--- Monitoring ---${RESET}"
prompt_yesno ICINGA2_ENABLED "Enable Icinga2?" "${ICINGA2_ENABLED:-n}"
if [[ "$ICINGA2_ENABLED" == "true" ]]; then
  prompt ICINGA2_MASTER "Icinga2 master hostname" "${ICINGA2_MASTER:-}"
fi
echo ""

# --- OdooKit ---
echo -e "${BOLD}--- OdooKit ---${RESET}"
ODOOKIT_REPO="${ODOOKIT_REPO:-https://github.com/salsedge/odookit}"
prompt_yesno CLONE_ODOOKIT "Clone OdooKit into project?" "n"
echo ""

# --- Review ---
echo -e "${BOLD}--- Review ---${RESET}"
echo -e "  Project:     ${GREEN}${PROJECT_NAME}${RESET} (${ORGANIZATION})"
echo -e "  Domain:      ${GREEN}${PRIMARY_DOMAIN}${RESET} (${DOMAIN_MODE})"
if [[ "$DOMAIN_MODE" == "multi" ]] && [[ -n "${ALIAS_DOMAINS:-}" ]]; then
  echo -e "  Aliases:     ${GREEN}${ALIAS_DOMAINS}${RESET}"
fi
echo -e "  Admin email: ${GREEN}${ADMIN_EMAIL}${RESET}"
echo -e "  Region:      ${GREEN}${DO_REGION}${RESET} / ${DROPLET_SIZE} / ${VOLUME_SIZE_GB}GB"
echo -e "  Database:    ${GREEN}${DB_NAME}${RESET} / ${DB_USER}"
echo -e "  TF bucket:   ${GREEN}${TFSTATE_BUCKET}${RESET}"
echo -e "  Backup:      ${GREEN}${BACKUP_BUCKET}${RESET} (${BACKUP_RETENTION_DAYS} days)"
echo -e "  Icinga2:     ${GREEN}${ICINGA2_ENABLED}${RESET}"
echo ""

prompt_yesno CONFIRM "Write instance.conf and generate configs?" "y"

if [[ "$CONFIRM" != "true" ]]; then
  echo "Aborted."
  exit 0
fi

# --- Write instance.conf ---
cat > "$INSTANCE_CONF" << EOF
# Instance Configuration — generated by setup.sh
# Re-run: make init (or edit this file and run: make generate)

# --- Project Identity ---
PROJECT_NAME="${PROJECT_NAME}"
ORGANIZATION="${ORGANIZATION}"

# --- Domain Configuration ---
DOMAIN_MODE="${DOMAIN_MODE}"
PRIMARY_DOMAIN="${PRIMARY_DOMAIN}"
ALIAS_DOMAINS="${ALIAS_DOMAINS:-}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

# --- DigitalOcean Infrastructure ---
DO_REGION="${DO_REGION}"
DROPLET_SIZE="${DROPLET_SIZE}"
VOLUME_SIZE_GB="${VOLUME_SIZE_GB}"
SSH_KEY_FINGERPRINT="${SSH_KEY_FINGERPRINT}"
SSH_PORT="${SSH_PORT}"

# --- Database ---
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"

# --- Spaces (Object Storage) ---
TFSTATE_BUCKET="${TFSTATE_BUCKET}"
BACKUP_BUCKET="${BACKUP_BUCKET}"
SPACES_REGION="${SPACES_REGION}"

# --- Backup ---
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS}"
BACKUP_NOTIFY_EMAIL="${BACKUP_NOTIFY_EMAIL}"

# --- Monitoring ---
ICINGA2_ENABLED="${ICINGA2_ENABLED}"
ICINGA2_MASTER="${ICINGA2_MASTER:-}"

# --- OdooKit ---
ODOOKIT_REPO="${ODOOKIT_REPO}"
EOF

echo -e "${GREEN}✓ instance.conf written${RESET}"

# --- Create Spaces bucket ---
echo ""
echo "Creating Spaces bucket: ${TFSTATE_BUCKET}..."

if command -v s3cmd >/dev/null 2>&1; then
  s3cmd mb "s3://${TFSTATE_BUCKET}" --region="${SPACES_REGION}" 2>/dev/null \
    && echo -e "${GREEN}✓ Bucket created: ${TFSTATE_BUCKET}${RESET}" \
    || echo -e "${YELLOW}Bucket may already exist or s3cmd not configured — verify manually${RESET}"
elif command -v doctl >/dev/null 2>&1; then
  echo -e "${YELLOW}doctl does not support Spaces bucket creation directly.${RESET}"
  echo "Create the bucket manually: https://cloud.digitalocean.com/spaces"
  echo "Bucket name: ${TFSTATE_BUCKET}, Region: ${SPACES_REGION}"
else
  echo -e "${YELLOW}Neither s3cmd nor doctl found.${RESET}"
  echo "Create the bucket manually: https://cloud.digitalocean.com/spaces"
  echo "Bucket name: ${TFSTATE_BUCKET}, Region: ${SPACES_REGION}"
fi

# --- Generate configs ---
echo ""
"${SCRIPT_DIR}/generate.sh"

# --- Clone OdooKit (optional) ---
if [[ "${CLONE_ODOOKIT:-false}" == "true" ]]; then
  echo ""
  echo "Cloning OdooKit..."
  if [[ -d "${SCRIPT_DIR}/odookit" ]]; then
    echo -e "${YELLOW}odookit/ already exists — skipping clone${RESET}"
  else
    git clone "${ODOOKIT_REPO}" "${SCRIPT_DIR}/odookit"
    echo -e "${GREEN}✓ OdooKit cloned to odookit/${RESET}"
  fi
fi

echo ""
echo -e "${GREEN}✓ Setup complete!${RESET}"
echo ""
echo "Next steps:"
echo "  1. Review generated configs in config/ and infra/"
echo "  2. Set environment variables: DIGITALOCEAN_TOKEN, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
echo "  3. make tf-init    # Initialize Terraform backend"
echo "  4. make tf-apply   # Provision infrastructure"
echo "  5. make deploy     # Deploy everything to droplet"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x setup.sh
```

- [ ] **Step 3: Run shellcheck**

```bash
shellcheck setup.sh
```

Fix any warnings.

- [ ] **Step 4: Commit**

```bash
git add setup.sh
git commit -m "feat: add setup.sh — interactive instance configuration wizard

Walks through instance.conf.example section by section with defaults,
validation, and review. Writes instance.conf, creates Spaces bucket,
calls generate.sh, and optionally clones OdooKit."
```

---

## Task 9: Rewrite Makefile

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Read current Makefile**

```bash
cat Makefile
```

- [ ] **Step 2: Rewrite Makefile for template workflow**

Replace the full Makefile contents with:

```makefile
# =============================================================================
# Odoo Droplet Template — Makefile
# =============================================================================
# Template lifecycle: init → tf-init → tf-apply → deploy
#
# Required env vars for infrastructure:
#   DIGITALOCEAN_TOKEN, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# =============================================================================

.DEFAULT_GOAL := help

# Source .env if it exists (DIGITALOCEAN_TOKEN, AWS_ACCESS_KEY_ID, etc.)
-include .env
export

# Source instance.conf if it exists (for SSH_PORT, PROJECT_NAME, etc.)
-include instance.conf

# ---------------------------------------------------------------------------
# Configuration (derived from instance.conf or overridable)
# ---------------------------------------------------------------------------
SSH_PORT     ?= 9292
SSH_USER     ?= deploy
SSH_KEY      ?= ~/.ssh/id_ed25519
DOMAIN       ?= $(PRIMARY_DOMAIN)
CERT_EMAIL   ?= $(ADMIN_EMAIL)
ALIAS_DOMAIN ?=
ADDON_PATH   ?=
REMOTE_DIR   := /tmp/odoo-setup

# Derive volume mount from project name
VOLUME_MOUNT ?= /mnt/$(PROJECT_NAME)-data
RCLONE_REMOTE ?= spaces:$(BACKUP_BUCKET)

# Resolve droplet IP from terraform if not set
DROPLET_IP   ?= $(shell cd infra && terraform output -raw droplet_ip 2>/dev/null)

SSH_OPTS     := -o StrictHostKeyChecking=accept-new -i $(SSH_KEY)
SSH_CMD      := ssh $(SSH_OPTS) -p $(SSH_PORT) $(SSH_USER)@$(DROPLET_IP)
SCP_CMD      := scp $(SSH_OPTS) -P $(SSH_PORT)

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

.PHONY: init
init: ## Interactive setup → instance.conf → generate all configs
	@./setup.sh

.PHONY: generate
generate: ## Re-generate configs from instance.conf (no prompts)
	@./generate.sh

.PHONY: validate
validate: ## Pre-flight: instance.conf exists, configs generated, Terraform valid
	@[ -f instance.conf ] || { echo "ERROR: instance.conf not found. Run 'make init' first."; exit 1; }
	@[ -f infra/backend.tf ] || { echo "ERROR: infra/backend.tf not found. Run 'make generate' first."; exit 1; }
	@[ -f config/.env ] || { echo "ERROR: config/.env not found. Run 'make generate' first."; exit 1; }
	@echo "Validating Terraform..."
	@cd infra && terraform validate
	@echo "All checks passed."

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------

.PHONY: tf-init
tf-init: ## Initialize Terraform backend and providers
	cd infra && terraform init

.PHONY: tf-plan
tf-plan: ## Preview infrastructure changes
	cd infra && terraform plan

.PHONY: tf-apply
tf-apply: ## Provision/update DigitalOcean infrastructure
	cd infra && terraform apply

.PHONY: tf-output
tf-output: ## Show Terraform outputs (droplet IP, volume path, etc.)
	cd infra && terraform output

.PHONY: tf-destroy
tf-destroy: ## Destroy all infrastructure (interactive confirmation)
	cd infra && terraform destroy

# ---------------------------------------------------------------------------
# Deployment — upload files to droplet
# ---------------------------------------------------------------------------

.PHONY: upload
upload: ## Upload config/ and scripts/ to droplet
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set and terraform output unavailable"; exit 1; }
	$(SSH_CMD) "sudo rm -rf $(REMOTE_DIR) && mkdir -p $(REMOTE_DIR)"
	$(SCP_CMD) -r config/ $(SSH_USER)@$(DROPLET_IP):$(REMOTE_DIR)/
	$(SCP_CMD) -r scripts/ $(SSH_USER)@$(DROPLET_IP):$(REMOTE_DIR)/
	@echo "Uploaded to $(SSH_USER)@$(DROPLET_IP):$(REMOTE_DIR)"

# ---------------------------------------------------------------------------
# Remote script execution
# ---------------------------------------------------------------------------

.PHONY: deploy-phase1
deploy-phase1: ## Run 01-harden-host.sh (requires SSH_USER=root for first run)
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/01-harden-host.sh"

.PHONY: deploy-phase2
deploy-phase2: ## Run 02-install-docker.sh
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/02-install-docker.sh"

.PHONY: deploy-phase3
deploy-phase3: ## Run 03-deploy-stack.sh
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD) "VOLUME_MOUNT=$(VOLUME_MOUNT) sudo -E bash $(REMOTE_DIR)/scripts/03-deploy-stack.sh"

.PHONY: deploy-phase4
deploy-phase4: ## Run 04-setup-nginx.sh
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	@[ -n "$(DOMAIN)" ] || { echo "ERROR: DOMAIN not set. Check instance.conf PRIMARY_DOMAIN."; exit 1; }
	@[ -n "$(CERT_EMAIL)" ] || { echo "ERROR: CERT_EMAIL not set. Check instance.conf ADMIN_EMAIL."; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/04-setup-nginx.sh $(DOMAIN) $(CERT_EMAIL)"

.PHONY: deploy-phase5
deploy-phase5: upload ## Upload files and run 05-setup-backups.sh
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD) "VOLUME_MOUNT=$(VOLUME_MOUNT) RCLONE_REMOTE=$(RCLONE_REMOTE) sudo -E bash $(REMOTE_DIR)/scripts/05-setup-backups.sh"

.PHONY: deploy
deploy: upload deploy-phase1 deploy-phase2 deploy-phase3 deploy-phase4 deploy-phase5 ## Full pipeline: upload → harden → docker → stack → nginx → backups

# ---------------------------------------------------------------------------
# Operations — day-2 tasks
# ---------------------------------------------------------------------------

.PHONY: set-domain
set-domain: upload ## Change primary domain (requires DOMAIN, CERT_EMAIL; optional ALIAS_DOMAIN)
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	@[ -n "$(DOMAIN)" ] || { echo "ERROR: DOMAIN not set"; exit 1; }
	@[ -n "$(CERT_EMAIL)" ] || { echo "ERROR: CERT_EMAIL not set"; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/ops/set-domain.sh $(DOMAIN) $(CERT_EMAIL) $(ALIAS_DOMAIN)"

.PHONY: deploy-addon
deploy-addon: upload ## Deploy custom Odoo module (requires ADDON_PATH=local/path/to/module)
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	@[ -n "$(ADDON_PATH)" ] || { echo "ERROR: ADDON_PATH not set"; exit 1; }
	@[ -d "$(ADDON_PATH)" ] || { echo "ERROR: $(ADDON_PATH) is not a directory"; exit 1; }
	$(SCP_CMD) -r $(ADDON_PATH) $(SSH_USER)@$(DROPLET_IP):/opt/odoo/custom-addons/
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/ops/deploy-addon.sh $$(basename $(ADDON_PATH))"

.PHONY: ssh
ssh: ## Open SSH session to droplet
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD)

.PHONY: status
status: ## Check remote service status (Docker, Odoo, Nginx)
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	@echo "--- Docker ---"
	@$(SSH_CMD) "sudo docker compose -f /opt/odoo/docker-compose.yml ps" 2>/dev/null || echo "(not deployed yet)"
	@echo "--- Nginx ---"
	@$(SSH_CMD) "sudo systemctl is-active nginx" 2>/dev/null || echo "(not installed yet)"
	@echo "--- UFW ---"
	@$(SSH_CMD) "sudo ufw status numbered" 2>/dev/null || echo "(not configured yet)"

.PHONY: logs
logs: ## Tail Odoo container logs
	$(SSH_CMD) "sudo docker compose -f /opt/odoo/docker-compose.yml logs -f --tail=50 odoo"

.PHONY: logs-db
logs-db: ## Tail PostgreSQL container logs
	$(SSH_CMD) "sudo docker compose -f /opt/odoo/docker-compose.yml logs -f --tail=50 db"

.PHONY: logs-nginx
logs-nginx: ## Tail Nginx access and error logs
	$(SSH_CMD) "sudo tail -f /var/log/nginx/odoo-access.log /var/log/nginx/odoo-error.log"

.PHONY: backup-now
backup-now: ## Trigger a manual backup
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD) "VOLUME_MOUNT=$(VOLUME_MOUNT) sudo -E bash /opt/odoo/scripts/06-backup-daily.sh"

.PHONY: test
test: ## Run OdooKit E2E tests (requires odookit/ directory)
	@if [ -d odookit ]; then \
		cd odookit && npm test; \
	else \
		echo "OdooKit not installed. Clone it:"; \
		echo "  git clone https://github.com/salsedge/odookit odookit/"; \
	fi

# ---------------------------------------------------------------------------
# Local validation
# ---------------------------------------------------------------------------

.PHONY: lint
lint: ## Shellcheck all deployment scripts
	shellcheck scripts/*.sh scripts/ops/*.sh setup.sh generate.sh

.PHONY: check
check: validate lint ## Run all local checks (terraform validate + shellcheck)

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

.PHONY: clean
clean: ## Remove generated files (keeps instance.conf)
	rm -f infra/backend.tf infra/terraform.tfvars
	rm -f config/.env config/odoo.conf config/docker-compose.yml
	rm -f config/nginx/odoo-pre-ssl.conf config/nginx/odoo.conf
	rm -f config/rclone.conf config/msmtprc
	rm -f monitoring/icinga2/commands.conf
	@echo "Generated files removed. instance.conf preserved."

.PHONY: nuke
nuke: clean ## Remove everything including instance.conf (fresh start)
	rm -f instance.conf
	@echo "All instance-specific files removed."

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
```

- [ ] **Step 3: Verify help target works**

```bash
make help
```

Expected: formatted list of all targets with descriptions.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: rewrite Makefile for template workflow

Replace Loodon-specific targets with template lifecycle: init,
generate, validate, deploy pipeline. Derive SSH/domain values
from instance.conf. Add clean/nuke, test delegation to OdooKit,
backup-now. Remove OdooKit-specific targets."
```

---

## Task 10: Rewrite README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read current README.md**

```bash
cat README.md
```

- [ ] **Step 2: Rewrite README.md as template usage guide**

Replace full contents. The README should cover:

1. **What this is** — one-paragraph summary
2. **Prerequisites** — DigitalOcean account, Terraform, `s3cmd` or `doctl`, SSH key
3. **Quickstart** — `make init` → `make tf-init` → `make tf-apply` → `make deploy`
4. **Configuration reference** — table of `instance.conf` keys with descriptions
5. **Architecture** — brief overview (single droplet, Docker Compose, Nginx on host, UFW)
6. **Day-2 operations** — `make set-domain`, `make deploy-addon`, `make backup-now`, `make ssh`
7. **Companion tools** — OdooKit section with link
8. **Regenerating configs** — `make generate` after editing `instance.conf`
9. **Destroying an instance** — `make tf-destroy`

Keep it concise — link to `docs/` for detailed guides.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README as template usage guide

Replace Loodon-specific documentation with quickstart, configuration
reference, architecture overview, day-2 operations, and companion
tools sections."
```

---

## Task 11: Rewrite CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read current CLAUDE.md**

```bash
cat CLAUDE.md
```

- [ ] **Step 2: Rewrite CLAUDE.md for template context**

Update the project summary, directory structure, conventions, key decisions, and status sections to reflect the template (not a specific deployment). Remove:
- Loodon-specific status references (`45.55.164.120`, `loodon-prod-01-odoo`)
- Phase completion tracking (no longer relevant)
- `.planning/` directory references
- OdooKit directory references
- Specific droplet details

Add:
- Template lifecycle explanation (`make init` → `make generate` → deploy)
- `instance.conf` as source of truth
- Generated vs. static file distinction
- `.example` file convention

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: rewrite CLAUDE.md for template context

Replace Loodon deployment status with template lifecycle, instance.conf
convention, generated vs static file distinction, and .example pattern."
```

---

## Task 12: Generalize Remaining Docs

**Files:**
- Modify: `docs/deployment-runbook.md`
- Modify: `docs/operations.md`
- Modify: `docs/architecture.md`

- [ ] **Step 1: Read and generalize docs/deployment-runbook.md**

```bash
cat docs/deployment-runbook.md
```

Replace all Loodon-specific references:
- `odoo-prod-tfstate` → `{PROJECT_NAME}-tfstate` (reference to instance.conf)
- `odoo-prod-backups` → `{PROJECT_NAME}-backups`
- `45.55.164.120` → `<droplet-ip>` or "from `terraform output`"
- `portal.loodon.com` → `{PRIMARY_DOMAIN}`
- `admin@loodon.com` → `{ADMIN_EMAIL}`
- Any `loodon` or `Loodon` references → generic

Add a note at the top: "Values in `{BRACES}` reference keys from `instance.conf`."

- [ ] **Step 2: Read and generalize docs/operations.md**

```bash
cat docs/operations.md
```

Same replacement pattern. Fold in any useful content from the deleted `docs/portal-domain-setup.md` (domain setup procedures).

- [ ] **Step 3: Read and generalize docs/architecture.md**

```bash
cat docs/architecture.md
```

Same replacement pattern. Update diagrams to use generic names.

- [ ] **Step 4: Commit**

```bash
git add docs/deployment-runbook.md docs/operations.md docs/architecture.md
git commit -m "docs: generalize deployment, operations, and architecture docs

Replace Loodon-specific domains, IPs, bucket names with instance.conf
key references. Fold portal domain setup content into operations."
```

---

## Task 13: Update .gitignore for docker-compose.yml and Final Verification

**Files:**
- Modify: `.gitignore` (add `config/docker-compose.yml` since it's now generated)

- [ ] **Step 1: Add docker-compose.yml to .gitignore**

The `.gitignore` from Task 3 didn't include `config/docker-compose.yml` since we only discovered in Task 4 that it needs to be generated (volume mount paths). Add it now.

Edit `.gitignore` — in the "Instance-specific (generated by generate.sh)" section, add:

```
config/docker-compose.yml
```

- [ ] **Step 2: Full grep for any remaining Loodon-specific references**

```bash
grep -rn 'loodon\|loomin\|portal\.loodon\|odoo\.loodon\|45\.55\.164\.120\|odoo-prod-tfstate\|odoo-prod-backups\|odoo-prod-data\|bibbeo\|BIBBEO' --include='*.md' --include='*.sh' --include='*.tf' --include='*.yml' --include='*.json' --include='*.conf' --include='*.env' --include='Makefile' .
```

Expected: no matches outside of:
- `docs/superpowers/specs/2026-03-31-template-conversion-design.md` (the spec itself, references are fine)
- `docs/superpowers/plans/2026-03-31-template-conversion.md` (this plan, references are fine)

Any other matches need to be cleaned up.

- [ ] **Step 3: Verify .example files are all committed**

```bash
git ls-files '*.example'
```

Expected list:
- `instance.conf.example`
- `infra/backend.tf.example`
- `infra/terraform.tfvars.example`
- `config/.env.example`
- `config/odoo.conf.example`
- `config/docker-compose.yml.example`
- `config/nginx/odoo-single.conf.example`
- `config/nginx/odoo-multi.conf.example`
- `config/nginx/odoo-pre-ssl.conf.example`
- `config/rclone.conf.example`
- `config/msmtprc.example`

- [ ] **Step 4: Verify generated files are NOT tracked**

```bash
git ls-files infra/backend.tf config/.env config/odoo.conf config/docker-compose.yml config/nginx/odoo.conf config/nginx/odoo-pre-ssl.conf config/rclone.conf config/msmtprc monitoring/icinga2/commands.conf instance.conf
```

Expected: no output (all gitignored)

- [ ] **Step 5: Run full lint check**

```bash
make lint
```

Expected: clean (or only pre-existing warnings)

- [ ] **Step 6: Commit**

```bash
git add .gitignore
git commit -m "chore: add docker-compose.yml to gitignore and verify cleanup"
```

---

## Task 14: End-to-End Smoke Test

**Files:** None (verification only)

- [ ] **Step 1: Start from clean state**

```bash
make nuke
```

Verify all generated files are gone.

- [ ] **Step 2: Copy example to instance.conf and generate**

```bash
cp instance.conf.example instance.conf
./generate.sh
```

Expected: all configs generated with demo defaults.

- [ ] **Step 3: Verify all generated files exist**

```bash
ls -la infra/backend.tf infra/terraform.tfvars config/.env config/odoo.conf config/docker-compose.yml config/nginx/odoo-pre-ssl.conf config/nginx/odoo.conf config/rclone.conf config/msmtprc
```

All should exist.

- [ ] **Step 4: Verify generated content is correct**

```bash
# Backend should have demo bucket name
grep 'odoo-demo-tfstate' infra/backend.tf

# Docker compose should have correct volume mount
grep '/mnt/odoo-demo-data' config/docker-compose.yml

# Nginx should have example domain
grep 'odoo.example.com' config/nginx/odoo.conf

# .env should have generated passwords (not CHANGE_ME)
grep -v 'CHANGE_ME' config/.env | grep 'POSTGRES_PASSWORD'
```

All should return matches.

- [ ] **Step 5: Test multi-domain mode**

Edit `instance.conf`:
- Set `DOMAIN_MODE="multi"`
- Set `ALIAS_DOMAINS="old.example.com"`

```bash
./generate.sh
grep 'old.example.com' config/nginx/odoo.conf
```

Expected: alias domain appears in Nginx config.

- [ ] **Step 6: Clean up**

```bash
make nuke
```

- [ ] **Step 7: Verify git status is clean**

```bash
git status
```

Expected: clean working tree (all generated files removed, no untracked files).
