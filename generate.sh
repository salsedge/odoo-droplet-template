#!/usr/bin/env bash
# =============================================================================
# generate.sh — Config generation engine for Odoo Droplet Template
# =============================================================================
# Reads instance.conf and produces all instance-specific config files.
# Safe to run multiple times — preserves passwords unless --force is passed.
#
# Usage:
#   ./generate.sh           # Generate/update configs, preserve passwords
#   ./generate.sh --force   # Regenerate everything including passwords
# =============================================================================

set -euo pipefail

# --- Globals -----------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE_CONF="${SCRIPT_DIR}/instance.conf"
FORCE=false

# --- Argument parsing --------------------------------------------------------

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    *) echo "ERROR: Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# --- Source instance.conf ----------------------------------------------------

if [[ ! -f "$INSTANCE_CONF" ]]; then
  echo "ERROR: instance.conf not found at ${INSTANCE_CONF}" >&2
  echo "       Copy instance.conf.example to instance.conf and customize it." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$INSTANCE_CONF"

# --- Resolve cascading defaults ----------------------------------------------

PROJECT_NAME="${PROJECT_NAME:-odoo-demo}"
ORGANIZATION="${ORGANIZATION:-My Organization}"
DOMAIN_MODE="${DOMAIN_MODE:-single}"
PRIMARY_DOMAIN="${PRIMARY_DOMAIN:-odoo.example.com}"
ALIAS_DOMAINS="${ALIAS_DOMAINS:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
DO_REGION="${DO_REGION:-nyc3}"
DROPLET_SIZE="${DROPLET_SIZE:-s-2vcpu-4gb}"
VOLUME_SIZE_GB="${VOLUME_SIZE_GB:-25}"
SSH_KEY_FINGERPRINT="${SSH_KEY_FINGERPRINT:-}"
SSH_PORT="${SSH_PORT:-9292}"
DB_NAME="${DB_NAME:-odoo-01}"
DB_USER="${DB_USER:-odoo}"
SPACES_REGION="${SPACES_REGION:-${DO_REGION}}"
TFSTATE_BUCKET="${TFSTATE_BUCKET:-${PROJECT_NAME}-tfstate}"
BACKUP_BUCKET="${BACKUP_BUCKET:-${PROJECT_NAME}-backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_NOTIFY_EMAIL="${BACKUP_NOTIFY_EMAIL:-${ADMIN_EMAIL}}"
ICINGA2_ENABLED="${ICINGA2_ENABLED:-false}"
ICINGA2_MASTER="${ICINGA2_MASTER:-}"

# --- Derived values ----------------------------------------------------------

# Block storage mount path: /mnt/<project-name>-data
VOLUME_MOUNT="/mnt/${PROJECT_NAME}-data"

# rclone remote path for backup bucket
RCLONE_REMOTE="spaces:${BACKUP_BUCKET}"

# SMTP from address derived from primary domain
SMTP_FROM_ADDR="alerts@${PRIMARY_DOMAIN}"

# For nginx multi-domain: extract first alias from comma-separated list
FIRST_ALIAS_DOMAIN=""
if [[ -n "$ALIAS_DOMAINS" ]]; then
  FIRST_ALIAS_DOMAIN="${ALIAS_DOMAINS%%,*}"
fi

# For nginx multi-domain: cert name is the primary domain (certbot default)
MULTI_CERT_NAME="${PRIMARY_DOMAIN}"

# --- Helpers -----------------------------------------------------------------

# Print status line
status() {
  local icon="$1"
  local msg="$2"
  echo "  ${icon} ${msg}"
}

# Prepend a generated-file header to a file (in-place)
# Usage: prepend_header <file> <comment_char>
prepend_header() {
  local file="$1"
  local comment="${2:-#}"
  local tmp
  tmp="$(mktemp)"
  {
    echo "${comment} Generated from instance.conf — do not edit directly. Re-run: make generate"
    cat "$file"
  } > "$tmp"
  mv "$tmp" "$file"
}

# --- Generate: infra/backend.tf ----------------------------------------------

generate_backend_tf() {
  local example="${SCRIPT_DIR}/infra/backend.tf.example"
  local output="${SCRIPT_DIR}/infra/backend.tf"

  sed \
    -e "s|SPACES_REGION|${SPACES_REGION}|g" \
    -e "s|TFSTATE_BUCKET_NAME|${TFSTATE_BUCKET}|g" \
    "$example" > "$output"

  prepend_header "$output" "#"
  status "+" "infra/backend.tf"
}

# --- Generate: infra/terraform.tfvars ----------------------------------------

generate_terraform_tfvars() {
  local output="${SCRIPT_DIR}/infra/terraform.tfvars"

  # Build SSH key section conditionally
  local ssh_key_block
  if [[ -n "$SSH_KEY_FINGERPRINT" ]]; then
    ssh_key_block="# SSH Key — fingerprint provided in instance.conf
use_existing_ssh_key = true
ssh_key_name         = \"${SSH_KEY_FINGERPRINT}\""
  else
    ssh_key_block="# SSH Key — no fingerprint set; will upload from ~/.ssh/id_ed25519.pub
use_existing_ssh_key = false
ssh_public_key_path  = \"~/.ssh/id_ed25519.pub\""
  fi

  cat > "$output" << TFVARS
# Generated from instance.conf — do not edit directly. Re-run: make generate
# =============================================================================
# Terraform Variables — ${PROJECT_NAME} (${ORGANIZATION})
# =============================================================================
# Secrets are passed via environment variables, not this file:
#   export DIGITALOCEAN_TOKEN="your-api-token"
#   export AWS_ACCESS_KEY_ID="your-spaces-access-key"
#   export AWS_SECRET_ACCESS_KEY="your-spaces-secret-key"
# =============================================================================

project_name   = "${PROJECT_NAME}"
region         = "${DO_REGION}"
droplet_size   = "${DROPLET_SIZE}"
volume_size_gb = ${VOLUME_SIZE_GB}

${ssh_key_block}

ssh_private_key_path = "~/.ssh/id_ed25519"
ssh_port             = ${SSH_PORT}

# WARNING: Restrict to your IP(s) for production use.
allowed_ssh_ips = ["0.0.0.0/0"]
TFVARS

  status "+" "infra/terraform.tfvars"
}

# --- Generate: config/.env ---------------------------------------------------

generate_env() {
  local output="${SCRIPT_DIR}/config/.env"
  local existing_pg_pass=""
  local existing_odoo_pass=""
  local preserved=""

  # Preserve passwords if file exists and not --force
  if [[ -f "$output" ]] && [[ "$FORCE" == "false" ]]; then
    existing_pg_pass="$(grep '^POSTGRES_PASSWORD=' "$output" | cut -d= -f2- || true)"
    existing_odoo_pass="$(grep '^ODOO_ADMIN_PASSWORD=' "$output" | cut -d= -f2- || true)"
    if [[ -n "$existing_pg_pass" ]] && [[ -n "$existing_odoo_pass" ]]; then
      preserved="true"
    fi
  fi

  # Generate new passwords if needed
  if [[ -z "$existing_pg_pass" ]]; then
    existing_pg_pass="$(openssl rand -base64 24 | tr -d '/+=')"
  fi
  if [[ -z "$existing_odoo_pass" ]]; then
    existing_odoo_pass="$(openssl rand -base64 24 | tr -d '/+=')"
  fi

  cat > "$output" << ENV
# Generated from instance.conf — do not edit directly. Re-run: make generate
# =============================================================================
# Environment Variables — ${PROJECT_NAME} (${ORGANIZATION})
# =============================================================================
# IMPORTANT: Contains secrets. Never commit to git.
# PASSWORD RULES: Do NOT use \$ or backticks. Safe chars: ! ^ * % & # @
# =============================================================================

# PostgreSQL credentials
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${existing_pg_pass}
POSTGRES_DB=${DB_NAME}

# Odoo admin master password (used for database management operations)
ODOO_ADMIN_PASSWORD=${existing_odoo_pass}

# =============================================================================
# Backup Offsite Sync — DO Spaces Credentials (BACK-02)
# =============================================================================
# Spaces-specific access keys — NOT the main DigitalOcean API token.
# Generate at: DigitalOcean Control Panel > API > Spaces Keys
SPACES_ACCESS_KEY=your_spaces_access_key
SPACES_SECRET_KEY=your_spaces_secret_key
SPACES_REGION=${SPACES_REGION}
BACKUP_BUCKET=${BACKUP_BUCKET}
RCLONE_REMOTE=${RCLONE_REMOTE}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS}

# =============================================================================
# Email Notifications — SMTP Relay for Backup Failures (BACK-01)
# =============================================================================
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_FROM=${SMTP_FROM_ADDR}
SMTP_USER=smtp_username
SMTP_PASSWORD=smtp_password
ALERT_EMAIL=${BACKUP_NOTIFY_EMAIL}
ENV

  chmod 600 "$output"

  if [[ "$FORCE" == "true" ]]; then
    status "+" "config/.env (passwords regenerated)"
  elif [[ "$preserved" == "true" ]]; then
    status "~" "config/.env (passwords preserved)"
  else
    status "+" "config/.env (passwords generated)"
  fi
}

# --- Generate: config/odoo.conf ----------------------------------------------

generate_odoo_conf() {
  local example="${SCRIPT_DIR}/config/odoo.conf.example"
  local output="${SCRIPT_DIR}/config/odoo.conf"

  # DB_PASSWORD_PLACEHOLDER and ADMIN_PASSWORD_PLACEHOLDER stay as tokens —
  # the deploy script replaces them at runtime from .env
  sed \
    -e "s|DB_USER_PLACEHOLDER|${DB_USER}|g" \
    -e "s|DB_NAME_PLACEHOLDER|${DB_NAME}|g" \
    "$example" > "$output"

  prepend_header "$output" ";"
  status "+" "config/odoo.conf"
}

# --- Generate: config/docker-compose.yml -------------------------------------

generate_docker_compose() {
  local example="${SCRIPT_DIR}/config/docker-compose.yml.example"
  local output="${SCRIPT_DIR}/config/docker-compose.yml"

  sed \
    -e "s|VOLUME_MOUNT_PLACEHOLDER|${VOLUME_MOUNT}|g" \
    "$example" > "$output"

  prepend_header "$output" "#"
  status "+" "config/docker-compose.yml"
}

# --- Generate: config/nginx/odoo-pre-ssl.conf --------------------------------

generate_nginx_pre_ssl() {
  local example="${SCRIPT_DIR}/config/nginx/odoo-pre-ssl.conf.example"
  local output="${SCRIPT_DIR}/config/nginx/odoo-pre-ssl.conf"

  sed \
    -e "s|DOMAIN_PLACEHOLDER|${PRIMARY_DOMAIN}|g" \
    "$example" > "$output"

  prepend_header "$output" "#"
  status "+" "config/nginx/odoo-pre-ssl.conf"
}

# --- Generate: config/nginx/odoo.conf ----------------------------------------

generate_nginx_ssl() {
  local output="${SCRIPT_DIR}/config/nginx/odoo.conf"

  if [[ "$DOMAIN_MODE" == "multi" ]]; then
    local example="${SCRIPT_DIR}/config/nginx/odoo-multi.conf.example"

    if [[ -z "$FIRST_ALIAS_DOMAIN" ]]; then
      echo "ERROR: DOMAIN_MODE=multi but ALIAS_DOMAINS is empty in instance.conf" >&2
      exit 1
    fi

    sed \
      -e "s|PRIMARY_DOMAIN|${PRIMARY_DOMAIN}|g" \
      -e "s|ALIAS_DOMAIN|${FIRST_ALIAS_DOMAIN}|g" \
      -e "s|CERT_NAME|${MULTI_CERT_NAME}|g" \
      "$example" > "$output"

    prepend_header "$output" "#"
    status "+" "config/nginx/odoo.conf (multi-domain: ${PRIMARY_DOMAIN} + ${FIRST_ALIAS_DOMAIN})"
  else
    # single mode: DOMAIN_PLACEHOLDER used for server_name AND cert paths
    local example="${SCRIPT_DIR}/config/nginx/odoo-single.conf.example"

    sed \
      -e "s|DOMAIN_PLACEHOLDER|${PRIMARY_DOMAIN}|g" \
      "$example" > "$output"

    prepend_header "$output" "#"
    status "+" "config/nginx/odoo.conf (single-domain: ${PRIMARY_DOMAIN})"
  fi
}

# --- Generate: config/rclone.conf --------------------------------------------

generate_rclone_conf() {
  local example="${SCRIPT_DIR}/config/rclone.conf.example"
  local output="${SCRIPT_DIR}/config/rclone.conf"

  # Substitute only the region — key placeholders stay for deploy script
  sed \
    -e "s|SPACES_REGION_PLACEHOLDER|${SPACES_REGION}|g" \
    "$example" > "$output"

  prepend_header "$output" "#"
  status "+" "config/rclone.conf"
}

# --- Generate: config/msmtprc ------------------------------------------------

generate_msmtprc() {
  local example="${SCRIPT_DIR}/config/msmtprc.example"
  local output="${SCRIPT_DIR}/config/msmtprc"

  # Substitute only the from address — other SMTP placeholders replaced at deploy time
  sed \
    -e "s|SMTP_FROM_PLACEHOLDER|${SMTP_FROM_ADDR}|g" \
    "$example" > "$output"

  prepend_header "$output" "#"
  status "+" "config/msmtprc"
}

# --- Generate: monitoring/icinga2/commands.conf (optional) -------------------

generate_icinga2_commands() {
  if [[ "$ICINGA2_ENABLED" != "true" ]]; then
    status "-" "monitoring/icinga2/commands.conf (skipped: ICINGA2_ENABLED != true)"
    return
  fi

  local example="${SCRIPT_DIR}/monitoring/icinga2/commands.conf.example"
  local output="${SCRIPT_DIR}/monitoring/icinga2/commands.conf"

  sed \
    -e "s|DB_USER_PLACEHOLDER|${DB_USER}|g" \
    -e "s|DB_NAME_PLACEHOLDER|${DB_NAME}|g" \
    "$example" > "$output"

  prepend_header "$output" "//"
  status "+" "monitoring/icinga2/commands.conf"
}

# --- Main --------------------------------------------------------------------

echo ""
echo "Generating configs from instance.conf..."
echo "  Project : ${PROJECT_NAME} (${ORGANIZATION})"
echo "  Domain  : ${PRIMARY_DOMAIN} [${DOMAIN_MODE}]"
echo "  Region  : ${DO_REGION} / Spaces: ${SPACES_REGION}"
echo "  Volume  : ${VOLUME_MOUNT}"
echo ""

generate_backend_tf
generate_terraform_tfvars
generate_env
generate_odoo_conf
generate_docker_compose
generate_nginx_pre_ssl
generate_nginx_ssl
generate_rclone_conf
generate_msmtprc
generate_icinga2_commands

echo ""
echo "Done. Next steps:"
echo ""
echo "  1. Fill in secrets in config/.env (Spaces keys, SMTP credentials)"
echo "  2. cd infra/ && terraform init && terraform plan"
echo "  3. terraform apply  — provisions droplet, volume, firewall"
echo "  4. Copy configs and scripts to the droplet:"
echo "       scp -r config/ scripts/ root@<droplet-ip>:/tmp/odoo-setup/"
echo "  5. SSH to droplet and run scripts 01 through 04 in order"
echo "       See README.md for the full deployment walkthrough"
echo ""
