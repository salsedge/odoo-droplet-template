#!/usr/bin/env bash
# =============================================================================
# setup.sh — Interactive instance configuration wizard for Odoo Droplet Template
# =============================================================================
# Walks through instance.conf.example section by section, prompts for each
# value with defaults, writes instance.conf, optionally creates a Spaces
# bucket, calls generate.sh, and optionally clones OdooKit.
#
# Usage:
#   ./setup.sh        # First run or idempotent re-run
# =============================================================================

set -euo pipefail

# --- Globals -----------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE_CONF="${SCRIPT_DIR}/instance.conf"
INSTANCE_CONF_EXAMPLE="${SCRIPT_DIR}/instance.conf.example"

# ANSI colours
BOLD=$'\033[1m'
CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RESET=$'\033[0m'

# cprint: colour-safe print — avoids SC2059 by using %s for the colour prefix
# Usage: cprint COLOUR "message"
cprint() {
  local colour="$1"
  local msg="$2"
  printf '%s%s%s\n' "$colour" "$msg" "$RESET"
}

# Collected values (populated by prompts)
PROJECT_NAME=""
ORGANIZATION=""
DOMAIN_MODE=""
PRIMARY_DOMAIN=""
ALIAS_DOMAINS=""
ADMIN_EMAIL=""
DO_REGION=""
DROPLET_SIZE=""
VOLUME_SIZE_GB=""
SSH_KEY_FINGERPRINT=""
SSH_PORT=""
DB_NAME=""
DB_USER=""
TFSTATE_BUCKET=""
BACKUP_BUCKET=""
SPACES_REGION=""
BACKUP_RETENTION_DAYS=""
BACKUP_NOTIFY_EMAIL=""
ICINGA2_ENABLED=""
ICINGA2_MASTER=""
CLONE_ODOOKIT=""
ODOOKIT_REPO=""

# --- Load existing values as defaults ----------------------------------------

# Source example first (provides baseline defaults)
if [[ -f "$INSTANCE_CONF_EXAMPLE" ]]; then
  # shellcheck source=/dev/null
  source "$INSTANCE_CONF_EXAMPLE"
fi

# Source existing instance.conf on top (overrides example with current values)
if [[ -f "$INSTANCE_CONF" ]]; then
  echo ""
  cprint "$YELLOW" "Found existing instance.conf — loading current values as defaults."
  # shellcheck source=/dev/null
  source "$INSTANCE_CONF"
fi

# Resolve any cascading defaults from example that use variable interpolation
TFSTATE_BUCKET="${TFSTATE_BUCKET:-${PROJECT_NAME}-tfstate}"
BACKUP_BUCKET="${BACKUP_BUCKET:-${PROJECT_NAME}-backups}"
SPACES_REGION="${SPACES_REGION:-${DO_REGION}}"
BACKUP_NOTIFY_EMAIL="${BACKUP_NOTIFY_EMAIL:-${ADMIN_EMAIL}}"

# --- Helper: prompt ----------------------------------------------------------
# Usage: prompt VARNAME "Prompt text" "default value"
# Reads user input; uses default if empty. Stores result in VARNAME.
prompt() {
  local varname="$1"
  local text="$2"
  local default="$3"
  local input

  if [[ -n "$default" ]]; then
    printf "  %s [%s]: " "$text" "$default"
  else
    printf "  %s: " "$text"
  fi

  read -r input
  if [[ -z "$input" ]]; then
    input="$default"
  fi

  printf -v "$varname" '%s' "$input"
}

# --- Helper: prompt_choice ---------------------------------------------------
# Usage: prompt_choice VARNAME "Prompt text" "opt1/opt2/..." "default"
prompt_choice() {
  local varname="$1"
  local text="$2"
  local options="$3"
  local default="$4"
  local input

  printf "  %s (%s) [%s]: " "$text" "$options" "$default"
  read -r input

  if [[ -z "$input" ]]; then
    input="$default"
  fi

  printf -v "$varname" '%s' "$input"
}

# --- Helper: prompt_yesno ----------------------------------------------------
# Usage: prompt_yesno VARNAME "Prompt text" "default (true|false)"
# Stores "true" or "false" in VARNAME.
prompt_yesno() {
  local varname="$1"
  local text="$2"
  local default="$3"
  local display_default input result

  if [[ "$default" == "true" ]]; then
    display_default="Y/n"
  else
    display_default="y/N"
  fi

  printf "  %s [%s]: " "$text" "$display_default"
  read -r input

  if [[ -z "$input" ]]; then
    result="$default"
  else
    case "${input,,}" in
      y|yes) result="true" ;;
      n|no)  result="false" ;;
      *)
        printf '%s  Warning: unrecognised input '\''%s'\'', using default '\''%s'\''%s\n' "$YELLOW" "$input" "$default" "$RESET"
        result="$default"
        ;;
    esac
  fi

  printf -v "$varname" '%s' "$result"
}

# --- Helper: validate_domain -------------------------------------------------
validate_domain() {
  local domain="$1"
  if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
    printf '%s  Warning: '\''%s'\'' does not look like a valid domain name.%s\n' "$YELLOW" "$domain" "$RESET"
  fi
}

# --- Helper: validate_port ---------------------------------------------------
validate_port() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    printf '%s  Warning: '\''%s'\'' is not a valid port number (1-65535).%s\n' "$YELLOW" "$port" "$RESET"
  fi
}

# --- Helper: validate_bucket -------------------------------------------------
validate_bucket() {
  local bucket="$1"
  # DO Spaces bucket names: 3-63 chars, lowercase, alphanumeric and hyphens
  if [[ ! "$bucket" =~ ^[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]$ ]]; then
    printf '%s  Warning: '\''%s'\'' may not be a valid Spaces bucket name (lowercase, alphanumeric, hyphens, 3-63 chars).%s\n' "$YELLOW" "$bucket" "$RESET"
  fi
}

# --- Section header ----------------------------------------------------------
section() {
  echo ""
  printf '%s%s--- %s %s\n' "$BOLD" "$CYAN" "$1" "$RESET"
  echo ""
}

# --- Interactive prompts -----------------------------------------------------

echo ""
printf '%s%sOdoo Droplet Template — Instance Configuration Wizard%s\n' "$BOLD" "$GREEN" "$RESET"
echo ""
echo "Press Enter to accept the default shown in [brackets]."
echo "Run again at any time to update values."

# --- Project Identity --------------------------------------------------------

section "Project Identity"

prompt PROJECT_NAME "Project name (slug, no spaces)" "${PROJECT_NAME:-odoo-demo}"
prompt ORGANIZATION "Organization display name" "${ORGANIZATION:-Acme Corp}"

# Recompute cascading bucket defaults after PROJECT_NAME is known
_default_tfstate_bucket="${PROJECT_NAME}-tfstate"
_default_backup_bucket="${PROJECT_NAME}-backups"

# --- Domain Configuration ----------------------------------------------------

section "Domain Configuration"

prompt_choice DOMAIN_MODE "Domain mode" "single/multi" "${DOMAIN_MODE:-single}"
prompt PRIMARY_DOMAIN "Primary domain (e.g. odoo.example.com)" "${PRIMARY_DOMAIN:-odoo.example.com}"
validate_domain "$PRIMARY_DOMAIN"

if [[ "$DOMAIN_MODE" == "multi" ]]; then
  prompt ALIAS_DOMAINS "Alias domains (comma-separated)" "${ALIAS_DOMAINS:-}"
fi

prompt ADMIN_EMAIL "Admin email (Let's Encrypt + Odoo)" "${ADMIN_EMAIL:-admin@example.com}"

# Recompute backup notify default after ADMIN_EMAIL is known
_default_backup_email="${BACKUP_NOTIFY_EMAIL:-${ADMIN_EMAIL}}"

# --- DigitalOcean Infrastructure ---------------------------------------------

section "DigitalOcean Infrastructure"

prompt DO_REGION "DO region slug" "${DO_REGION:-nyc3}"
prompt DROPLET_SIZE "Droplet size slug" "${DROPLET_SIZE:-s-2vcpu-4gb}"
prompt VOLUME_SIZE_GB "Block storage volume size (GB)" "${VOLUME_SIZE_GB:-25}"
prompt SSH_KEY_FINGERPRINT "SSH key fingerprint (leave blank to upload ~/.ssh/id_ed25519.pub)" "${SSH_KEY_FINGERPRINT:-}"
prompt SSH_PORT "SSH port" "${SSH_PORT:-9292}"
validate_port "$SSH_PORT"

# --- Database ----------------------------------------------------------------

section "Database"

prompt DB_NAME "PostgreSQL database name" "${DB_NAME:-odoo-01}"
prompt DB_USER "PostgreSQL user" "${DB_USER:-odoo}"

# --- Spaces (Object Storage) -------------------------------------------------

section "Spaces (Object Storage)"

prompt SPACES_REGION "Spaces region slug" "${SPACES_REGION:-${DO_REGION}}"
prompt TFSTATE_BUCKET "Terraform state bucket name" "${TFSTATE_BUCKET:-${_default_tfstate_bucket}}"
validate_bucket "$TFSTATE_BUCKET"
prompt BACKUP_BUCKET "Backup bucket name" "${BACKUP_BUCKET:-${_default_backup_bucket}}"
validate_bucket "$BACKUP_BUCKET"

# --- Backup ------------------------------------------------------------------

section "Backup"

prompt BACKUP_RETENTION_DAYS "Backup retention (days)" "${BACKUP_RETENTION_DAYS:-30}"
prompt BACKUP_NOTIFY_EMAIL "Backup notification email" "${_default_backup_email}"

# --- Monitoring --------------------------------------------------------------

section "Monitoring"

prompt_yesno ICINGA2_ENABLED "Enable Icinga2 monitoring agent" "${ICINGA2_ENABLED:-false}"

if [[ "$ICINGA2_ENABLED" == "true" ]]; then
  prompt ICINGA2_MASTER "Icinga2 master hostname" "${ICINGA2_MASTER:-}"
fi

# --- OdooKit -----------------------------------------------------------------

section "OdooKit (optional)"

prompt_yesno CLONE_ODOOKIT "Clone OdooKit repository after setup" "false"

if [[ "$CLONE_ODOOKIT" == "true" ]]; then
  prompt ODOOKIT_REPO "OdooKit repository URL" "${ODOOKIT_REPO:-https://github.com/salsedge/odookit}"
else
  ODOOKIT_REPO="${ODOOKIT_REPO:-https://github.com/salsedge/odookit}"
fi

# --- Review summary ----------------------------------------------------------

echo ""
printf '%s%s=== Review ===%s\n' "$BOLD" "$CYAN" "$RESET"
echo ""
printf "  %-30s %s\n" "PROJECT_NAME"          "$PROJECT_NAME"
printf "  %-30s %s\n" "ORGANIZATION"          "$ORGANIZATION"
printf "  %-30s %s\n" "DOMAIN_MODE"           "$DOMAIN_MODE"
printf "  %-30s %s\n" "PRIMARY_DOMAIN"        "$PRIMARY_DOMAIN"
if [[ "$DOMAIN_MODE" == "multi" ]]; then
  printf "  %-30s %s\n" "ALIAS_DOMAINS"       "$ALIAS_DOMAINS"
fi
printf "  %-30s %s\n" "ADMIN_EMAIL"           "$ADMIN_EMAIL"
printf "  %-30s %s\n" "DO_REGION"             "$DO_REGION"
printf "  %-30s %s\n" "DROPLET_SIZE"          "$DROPLET_SIZE"
printf "  %-30s %s\n" "VOLUME_SIZE_GB"        "$VOLUME_SIZE_GB"
printf "  %-30s %s\n" "SSH_KEY_FINGERPRINT"   "${SSH_KEY_FINGERPRINT:-(will upload pub key)}"
printf "  %-30s %s\n" "SSH_PORT"              "$SSH_PORT"
printf "  %-30s %s\n" "DB_NAME"               "$DB_NAME"
printf "  %-30s %s\n" "DB_USER"               "$DB_USER"
printf "  %-30s %s\n" "SPACES_REGION"         "$SPACES_REGION"
printf "  %-30s %s\n" "TFSTATE_BUCKET"        "$TFSTATE_BUCKET"
printf "  %-30s %s\n" "BACKUP_BUCKET"         "$BACKUP_BUCKET"
printf "  %-30s %s\n" "BACKUP_RETENTION_DAYS" "$BACKUP_RETENTION_DAYS"
printf "  %-30s %s\n" "BACKUP_NOTIFY_EMAIL"   "$BACKUP_NOTIFY_EMAIL"
printf "  %-30s %s\n" "ICINGA2_ENABLED"       "$ICINGA2_ENABLED"
if [[ "$ICINGA2_ENABLED" == "true" ]]; then
  printf "  %-30s %s\n" "ICINGA2_MASTER"      "$ICINGA2_MASTER"
fi
printf "  %-30s %s\n" "ODOOKIT_REPO"          "$ODOOKIT_REPO"
echo ""

# --- Confirm -----------------------------------------------------------------

printf "  Write instance.conf and run generate.sh? [Y/n]: "
read -r _confirm
if [[ "${_confirm,,}" == "n" || "${_confirm,,}" == "no" ]]; then
  echo ""
  echo "Aborted — no files written."
  exit 0
fi

# --- Write instance.conf -----------------------------------------------------

cat > "$INSTANCE_CONF" << CONF
# =============================================================================
# Instance Configuration — ${PROJECT_NAME} (${ORGANIZATION})
# =============================================================================
# Generated by setup.sh on $(date -u '+%Y-%m-%d %H:%M UTC')
# Re-run setup.sh to update, or edit directly.
# =============================================================================

# --- Project Identity ---
PROJECT_NAME="${PROJECT_NAME}"
ORGANIZATION="${ORGANIZATION}"

# --- Domain Configuration ---
DOMAIN_MODE="${DOMAIN_MODE}"              # "single" or "multi"
PRIMARY_DOMAIN="${PRIMARY_DOMAIN}"
ALIAS_DOMAINS="${ALIAS_DOMAINS}"          # Comma-separated, only used if DOMAIN_MODE=multi
ADMIN_EMAIL="${ADMIN_EMAIL}"              # Let's Encrypt + Odoo admin notifications

# --- DigitalOcean Infrastructure ---
DO_REGION="${DO_REGION}"
DROPLET_SIZE="${DROPLET_SIZE}"
VOLUME_SIZE_GB="${VOLUME_SIZE_GB}"
SSH_KEY_FINGERPRINT="${SSH_KEY_FINGERPRINT}"  # Leave blank to upload ~/.ssh/id_ed25519.pub
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

# --- Monitoring (optional) ---
ICINGA2_ENABLED="${ICINGA2_ENABLED}"
ICINGA2_MASTER="${ICINGA2_MASTER}"        # Hostname of Icinga2 master

# --- OdooKit (optional) ---
ODOOKIT_REPO="${ODOOKIT_REPO}"
CONF

cprint "$GREEN" "  Written: instance.conf"

# --- Create Spaces bucket (optional, graceful failure) -----------------------

echo ""
echo "Attempting to create Spaces backup bucket: ${BACKUP_BUCKET} in ${SPACES_REGION}..."

_bucket_created=false

if command -v s3cmd &> /dev/null; then
  if s3cmd mb "s3://${BACKUP_BUCKET}" --region="${SPACES_REGION}" 2>/dev/null; then
    printf '%s  Bucket created via s3cmd: %s%s\n' "$GREEN" "$BACKUP_BUCKET" "$RESET"
    _bucket_created=true
  else
    cprint "$YELLOW" "  s3cmd: bucket creation skipped (may already exist, or credentials not configured)."
  fi
elif command -v doctl &> /dev/null; then
  if doctl compute cdn create --origin "${BACKUP_BUCKET}.${SPACES_REGION}.digitaloceanspaces.com" &>/dev/null || \
     doctl spaces create "${BACKUP_BUCKET}" --region "${SPACES_REGION}" 2>/dev/null; then
    printf '%s  Bucket created via doctl: %s%s\n' "$GREEN" "$BACKUP_BUCKET" "$RESET"
    _bucket_created=true
  else
    cprint "$YELLOW" "  doctl: bucket creation skipped (may already exist, or not authenticated)."
  fi
else
  cprint "$YELLOW" "  Neither s3cmd nor doctl found — skipping automatic bucket creation."
  cprint "$YELLOW" "  Create manually: DigitalOcean Control Panel > Spaces > New Bucket"
fi

if [[ "$_bucket_created" == "false" ]]; then
  printf "  Bucket: %s (create manually if needed)\n" "$BACKUP_BUCKET"
fi

# --- Run generate.sh ---------------------------------------------------------

echo ""
echo "Running generate.sh..."
echo ""

if [[ ! -f "${SCRIPT_DIR}/generate.sh" ]]; then
  printf '%s  Warning: generate.sh not found at %s — skipping.%s\n' "$YELLOW" "${SCRIPT_DIR}/generate.sh" "$RESET"
else
  bash "${SCRIPT_DIR}/generate.sh"
fi

# --- Clone OdooKit -----------------------------------------------------------

if [[ "$CLONE_ODOOKIT" == "true" ]]; then
  echo ""
  echo "Cloning OdooKit..."
  _odookit_dir="${SCRIPT_DIR}/odookit"

  if [[ -d "$_odookit_dir" ]]; then
    printf '%s  Directory already exists: %s — skipping clone.%s\n' "$YELLOW" "$_odookit_dir" "$RESET"
  else
    if git clone "$ODOOKIT_REPO" "$_odookit_dir"; then
      printf '%s  OdooKit cloned to: %s%s\n' "$GREEN" "$_odookit_dir" "$RESET"
    else
      cprint "$YELLOW" "  Warning: git clone failed. Check the URL and your network access."
    fi
  fi
fi

# --- Next steps --------------------------------------------------------------

echo ""
printf '%s%sSetup complete.%s Next steps:\n' "$BOLD" "$GREEN" "$RESET"
echo ""
echo "  1. Fill in secrets in config/.env:"
echo "       SPACES_ACCESS_KEY, SPACES_SECRET_KEY, SMTP credentials"
echo ""
echo "  2. Export Terraform credentials:"
echo "       export DIGITALOCEAN_TOKEN=\"your-api-token\""
echo "       export AWS_ACCESS_KEY_ID=\"your-spaces-access-key\""
echo "       export AWS_SECRET_ACCESS_KEY=\"your-spaces-secret-key\""
echo ""
echo "  3. Provision infrastructure:"
echo "       cd infra/ && terraform init && terraform plan && terraform apply"
echo ""
echo "  4. Copy configs and scripts to the droplet:"
echo "       scp -r config/ scripts/ root@<droplet-ip>:/tmp/odoo-setup/"
echo ""
echo "  5. SSH to the droplet and run scripts 01 through 04 in order:"
echo "       ssh root@<droplet-ip>"
echo "       bash /tmp/odoo-setup/scripts/01-harden-host.sh"
echo "       # Reconnect on new port after 01:"
printf "       ssh -p %s deploy@<droplet-ip>\n" "$SSH_PORT"
echo "       sudo bash /tmp/odoo-setup/scripts/02-install-docker.sh"
echo "       sudo bash /tmp/odoo-setup/scripts/03-deploy-stack.sh"
printf "       sudo bash /tmp/odoo-setup/scripts/04-setup-nginx.sh %s %s\n" "$PRIMARY_DOMAIN" "$ADMIN_EMAIL"
echo ""
