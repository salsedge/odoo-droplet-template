# Phase 1: Terraform Foundation and Compute - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Provision all DigitalOcean infrastructure via Terraform — VPC, cloud firewall, Ubuntu 24.04 droplet, Block Storage Volume, and DO Spaces remote state backend. The provisioner verifies SSH and volume mount only; hardening, Docker, and application deployment are Phase 2.

</domain>

<decisions>
## Implementation Decisions

### Module structure
- Terraform files live in `infra/` directory at repo root
- Bash provisioning scripts live in `scripts/` directory at repo root
- Config templates (docker-compose.yml, nginx.conf, odoo.conf, etc.) live in `config/` directory at repo root
- Claude decides flat vs modular .tf file organization based on project scale

### Resource sizing
- Droplet: `s-2vcpu-4gb` ($24/mo) — tight but workable for 10 users
- Block Storage Volume: 25 GB — PostgreSQL data + Odoo filestore only, no local backups
- Backups go to DO Spaces only (no local backup retention on volume)
- Region: nyc1 or nyc3 (US East)
- SSH keys: support both existing DO key (by fingerprint) and upload from local public key file, controlled via tfvars toggle

### State backend
- Remote state stored in DO Spaces (S3-compatible backend)
- Spaces bucket created manually as a one-time bootstrap step (documented in runbook)
- No state locking needed — single operator, collision risk near zero
- Secrets passed via environment variables (primary) or .gitignored terraform.tfvars (documented fallback)

### Provisioning
- Terraform uses `remote-exec` provisioner to SSH into droplet after creation
- Phase 1 provisioner is minimal: verify SSH connectivity and volume mount only
- Docker installation, hardening, and all application setup happen in Phase 2 scripts
- DNS managed externally — Terraform outputs the droplet IP, user updates DNS manually
- Production resources (droplet, volume) have `lifecycle { prevent_destroy = true }` protection

### Claude's Discretion
- Flat vs modular Terraform file organization
- Exact VPC CIDR range and subnet configuration
- Firewall rule specifics beyond SSH/HTTP/HTTPS
- Terraform provider version pinning strategy
- .gitignore entries for Terraform artifacts

</decisions>

<specifics>
## Specific Ideas

- User has a 24-hour RTO tolerance — local backup volume is explicitly deferred to save cost; Spaces-only backup is acceptable
- Repo structure: `infra/` (Terraform), `scripts/` (bash), `config/` (templates), `docs/` (documentation), `artifacts/` (reference materials)
- Bootstrap is a documented manual step: create Spaces bucket, then `terraform init`

</specifics>

<deferred>
## Deferred Ideas

- Local backup volume for faster restore — revisit if Spaces restore time exceeds 24-hour RTO
- DNS management in Terraform — currently external, could add DO DNS module later
- State locking — add if team grows beyond single operator

</deferred>

---

*Phase: 01-terraform-foundation-and-compute*
*Context gathered: 2026-02-21*
