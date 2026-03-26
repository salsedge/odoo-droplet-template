# =============================================================================
# Odoo 19.x Production Build — Makefile
# =============================================================================
# Wraps Terraform, SCP deployment, and remote script execution.
#
# Required env vars for infrastructure:
#   DIGITALOCEAN_TOKEN, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#
# Configuration:
#   DROPLET_IP    — set manually or auto-resolved from terraform output
#   SSH_PORT      — defaults to 9292 (post-hardening)
#   SSH_USER      — defaults to deploy (use root for first run)
#   DOMAIN        — required for nginx/ssl setup
#   CERT_EMAIL    — required for certbot registration
# =============================================================================

.DEFAULT_GOAL := help

# Source .env if it exists (DIGITALOCEAN_TOKEN, AWS_ACCESS_KEY_ID, etc.)
-include .env
export

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SSH_PORT     ?= 9292
SSH_USER     ?= deploy
SSH_KEY      ?= ~/.ssh/id_ed25519
DOMAIN       ?=
CERT_EMAIL   ?=
ALIAS_DOMAIN ?=
REMOTE_DIR   := /tmp/odoo-setup

# Resolve droplet IP from terraform if not set
DROPLET_IP   ?= $(shell cd infra && AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID) AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY) terraform output -raw droplet_ip 2>/dev/null)

SSH_OPTS     := -o StrictHostKeyChecking=accept-new -i $(SSH_KEY)
SSH_CMD      := ssh $(SSH_OPTS) -p $(SSH_PORT) $(SSH_USER)@$(DROPLET_IP)
SCP_CMD      := scp $(SSH_OPTS) -P $(SSH_PORT)

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

.PHONY: run-harden
run-harden: ## Run 01-harden-host.sh on droplet (requires root, SSH_USER=root)
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/01-harden-host.sh"

.PHONY: run-docker
run-docker: ## Run 02-install-docker.sh on droplet
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/02-install-docker.sh"

.PHONY: run-stack
run-stack: ## Run 03-deploy-stack.sh on droplet
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/03-deploy-stack.sh"

.PHONY: run-nginx
run-nginx: ## Run 04-setup-nginx.sh on droplet (requires DOMAIN and CERT_EMAIL)
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	@[ -n "$(DOMAIN)" ] || { echo "ERROR: DOMAIN not set (e.g., make run-nginx DOMAIN=odoo.example.com CERT_EMAIL=admin@example.com)"; exit 1; }
	@[ -n "$(CERT_EMAIL)" ] || { echo "ERROR: CERT_EMAIL not set"; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/04-setup-nginx.sh $(DOMAIN) $(CERT_EMAIL)"

.PHONY: run-backups
run-backups: upload ## Upload files and run 05-setup-backups.sh on droplet
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/05-setup-backups.sh"

# ---------------------------------------------------------------------------
# Full deployment sequences
# ---------------------------------------------------------------------------

.PHONY: deploy-phase2
deploy-phase2: upload run-harden run-docker run-stack run-nginx ## Run full Phase 2 deployment (upload + all scripts in order)

.PHONY: deploy-host
deploy-host: upload run-harden run-docker ## Upload and run host hardening + Docker install

.PHONY: deploy-app
deploy-app: upload run-stack run-nginx ## Upload and deploy application stack + Nginx

# ---------------------------------------------------------------------------
# Operations — day-2 tasks (scripts/ops/)
# ---------------------------------------------------------------------------

.PHONY: set-domain
set-domain: upload ## Change primary domain (requires DOMAIN, CERT_EMAIL; optional ALIAS_DOMAIN)
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	@[ -n "$(DOMAIN)" ] || { echo "ERROR: DOMAIN not set (e.g., make set-domain DOMAIN=portal.example.com CERT_EMAIL=admin@example.com)"; exit 1; }
	@[ -n "$(CERT_EMAIL)" ] || { echo "ERROR: CERT_EMAIL not set"; exit 1; }
	$(SSH_CMD) "sudo bash $(REMOTE_DIR)/scripts/ops/set-domain.sh $(DOMAIN) $(CERT_EMAIL) $(ALIAS_DOMAIN)"

# ---------------------------------------------------------------------------
# Remote status checks
# ---------------------------------------------------------------------------

.PHONY: ssh
ssh: ## Open SSH session to droplet
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	$(SSH_CMD)

.PHONY: status
status: ## Check remote service status (Docker, Odoo, Nginx)
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	@echo "--- Docker ---"
	$(SSH_CMD) "sudo docker compose -f /opt/odoo/docker-compose.yml ps" 2>/dev/null || echo "(not deployed yet)"
	@echo "--- Nginx ---"
	$(SSH_CMD) "sudo systemctl is-active nginx" 2>/dev/null || echo "(not installed yet)"
	@echo "--- UFW ---"
	$(SSH_CMD) "sudo ufw status numbered" 2>/dev/null || echo "(not configured yet)"

.PHONY: logs-odoo
logs-odoo: ## Tail Odoo container logs
	$(SSH_CMD) "sudo docker compose -f /opt/odoo/docker-compose.yml logs -f --tail=50 odoo"

.PHONY: logs-postgres
logs-postgres: ## Tail PostgreSQL container logs
	$(SSH_CMD) "sudo docker compose -f /opt/odoo/docker-compose.yml logs -f --tail=50 postgres"

.PHONY: logs-nginx
logs-nginx: ## Tail Nginx access and error logs
	$(SSH_CMD) "sudo tail -f /var/log/nginx/odoo-access.log /var/log/nginx/odoo-error.log"

# ---------------------------------------------------------------------------
# OdooKit — test and verification
# ---------------------------------------------------------------------------

.PHONY: verify-prod
verify-prod: ## Run full production verification (tunnel, smoke, audit, users, backup)
	cd odookit && npm run verify:prod

.PHONY: verify-backup
verify-backup: ## Run backup verification only
	cd odookit && npm run verify:backup

.PHONY: test-local
test-local: ## Run OdooKit tests against local Docker Compose stack
	cd odookit && npm run test:local

# ---------------------------------------------------------------------------
# Local validation
# ---------------------------------------------------------------------------

.PHONY: lint
lint: ## Shellcheck all deployment scripts
	shellcheck scripts/*.sh scripts/ops/*.sh

.PHONY: validate
validate: ## Validate Terraform configuration
	cd infra && terraform validate

.PHONY: check
check: validate lint ## Run all local checks (terraform validate + shellcheck)

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
