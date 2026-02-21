# Phase 1: Terraform Foundation and Compute - Research

**Researched:** 2026-02-21
**Domain:** Terraform IaC with DigitalOcean provider (VPC, Firewall, Droplet, Block Storage, Spaces)
**Confidence:** HIGH

## Summary

Phase 1 provisions all DigitalOcean infrastructure via a single `terraform apply`: VPC with private networking, cloud firewall (SSH/HTTP/HTTPS only), Ubuntu 24.04 droplet (`s-2vcpu-4gb`), 25 GB Block Storage Volume (ext4, auto-mounted), and remote state stored in a pre-created DO Spaces bucket via the S3-compatible backend. The technology stack is mature, well-documented, and stable -- the DigitalOcean Terraform provider is actively maintained (v2.76.0, released 2026-02-16) and the S3 backend configuration for Spaces is officially documented by DigitalOcean.

The primary complexity lies in three areas: (1) correctly bootstrapping the Spaces bucket before `terraform init` since the backend bucket cannot be Terraform-managed, (2) handling volume attachment without creating drift (must use either inline `volume_ids` on the droplet OR `digitalocean_volume_attachment` resource, never both), and (3) configuring the `remote-exec` provisioner with proper SSH timeout handling since newly created droplets are not immediately SSH-ready. All three are well-understood patterns with documented solutions.

**Primary recommendation:** Use a flat Terraform file layout in `infra/` with separate files per concern (providers.tf, backend.tf, variables.tf, main.tf, outputs.tf, terraform.tfvars.example). Use `digitalocean_volume_attachment` as a separate resource (not inline `volume_ids`) for explicit dependency ordering and `prevent_destroy` compatibility. Bootstrap the Spaces bucket manually via the DO control panel as a documented one-time step.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Terraform files live in `infra/` directory at repo root
- Bash provisioning scripts live in `scripts/` directory at repo root
- Config templates (docker-compose.yml, nginx.conf, odoo.conf, etc.) live in `config/` directory at repo root
- Droplet: `s-2vcpu-4gb` ($24/mo) -- tight but workable for 10 users
- Block Storage Volume: 25 GB -- PostgreSQL data + Odoo filestore only, no local backups
- Backups go to DO Spaces only (no local backup retention on volume)
- Region: nyc1 or nyc3 (US East)
- SSH keys: support both existing DO key (by fingerprint) and upload from local public key file, controlled via tfvars toggle
- Remote state stored in DO Spaces (S3-compatible backend)
- Spaces bucket created manually as a one-time bootstrap step (documented in runbook)
- No state locking needed -- single operator, collision risk near zero
- Secrets passed via environment variables (primary) or .gitignored terraform.tfvars (documented fallback)
- Terraform uses `remote-exec` provisioner to SSH into droplet after creation
- Phase 1 provisioner is minimal: verify SSH connectivity and volume mount only
- Docker installation, hardening, and all application setup happen in Phase 2 scripts
- DNS managed externally -- Terraform outputs the droplet IP, user updates DNS manually
- Production resources (droplet, volume) have `lifecycle { prevent_destroy = true }` protection

### Claude's Discretion
- Flat vs modular Terraform file organization
- Exact VPC CIDR range and subnet configuration
- Firewall rule specifics beyond SSH/HTTP/HTTPS
- Terraform provider version pinning strategy
- .gitignore entries for Terraform artifacts

### Deferred Ideas (OUT OF SCOPE)
- Local backup volume for faster restore -- revisit if Spaces restore time exceeds 24-hour RTO
- DNS management in Terraform -- currently external, could add DO DNS module later
- State locking -- add if team grows beyond single operator
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| IAC-01 | Terraform provisions DigitalOcean VPC with private networking | `digitalocean_vpc` resource supports custom `ip_range` (CIDR /16 to /28), region assignment; droplets reference `vpc_uuid` for private networking |
| IAC-02 | Terraform provisions DO firewall rules (SSH, HTTP, HTTPS only) | `digitalocean_firewall` resource supports `inbound_rule`/`outbound_rule` blocks with protocol, port_range, source/destination_addresses; associate via `droplet_ids` or `tags` |
| IAC-03 | Terraform provisions Odoo application droplet (Ubuntu 24.04 LTS) | `digitalocean_droplet` resource with `image = "ubuntu-24-04-x64"`, `size = "s-2vcpu-4gb"`, `region`, `vpc_uuid`, `ssh_keys` arguments |
| IAC-04 | Terraform provisions and attaches DO Block Storage Volume for persistent data | `digitalocean_volume` resource with `initial_filesystem_type = "ext4"` + `digitalocean_volume_attachment` resource; DO auto-mounts pre-formatted volumes |
| IAC-05 | Terraform configures DO Spaces bucket for remote state backend | S3-compatible `backend "s3"` with `endpoints = { s3 = "https://nyc3.digitaloceanspaces.com" }`, five `skip_*` flags, `region = "us-east-1"` (dummy); bucket pre-created manually |
| IAC-06 | Terraform uses tfvars for environment-specific configuration | `variables.tf` declares all configurable values with `sensitive` flag on secrets; `terraform.tfvars.example` committed, actual `.tfvars` gitignored; env vars as primary secret mechanism |
| IAC-07 | Terraform executes bootstrap scripts via remote-exec provisioners | `remote-exec` provisioner with SSH `connection` block using `self.ipv4_address`, `timeout = "2m"`, inline commands to verify SSH and volume mount |
| IAC-08 | Terraform outputs critical info (droplet IP, volume mount path, Spaces endpoint) | `outputs.tf` exposes `digitalocean_droplet.*.ipv4_address`, volume mount path (constructed from volume name), Spaces endpoint URL |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Terraform | >= 1.6.3 (current: 1.14.5) | Infrastructure as Code engine | Industry standard IaC; required for S3 backend `endpoints` syntax (introduced 1.6.3) |
| digitalocean/digitalocean provider | ~> 2.0 (current: 2.76.0) | DigitalOcean resource management | Official provider, actively maintained, 80+ resource types |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| doctl (DigitalOcean CLI) | Latest | Bootstrap Spaces bucket creation | One-time manual setup before first `terraform init` |
| ssh-keygen | System | Generate SSH key pairs | If operator needs to create new keys for droplet access |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| remote-exec provisioner | cloud-init / user_data | cloud-init is more declarative but harder to debug; remote-exec gives immediate SSH verification. User explicitly chose remote-exec. |
| Flat file layout | Terraform modules | Modules add complexity for single-environment, ~6 resource deployments. Flat layout is recommended for this scale. |
| S3 backend (Spaces) | Terraform Cloud | Terraform Cloud adds dependency on external service; Spaces keeps everything in DO ecosystem |

### Installation

```bash
# Terraform (macOS via Homebrew)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Or download directly
# https://releases.hashicorp.com/terraform/1.14.5/

# DigitalOcean CLI (for Spaces bootstrap)
brew install doctl
doctl auth init  # authenticate with API token
```

## Architecture Patterns

### Recommended Project Structure

```
infra/
├── providers.tf          # Required providers + provider config
├── backend.tf            # S3 backend configuration (DO Spaces)
├── variables.tf          # All variable declarations with descriptions
├── main.tf               # All resource definitions (VPC, firewall, droplet, volume, attachment)
├── outputs.tf            # All output values
├── terraform.tfvars.example  # Template with placeholder values (committed to git)
└── .terraform.lock.hcl   # Provider lock file (committed to git)
```

**Rationale for flat layout:** With ~6 resources and a single environment, modules add overhead without benefit. Each `.tf` file has a clear single responsibility. This aligns with HashiCorp's recommendation for small projects.

### Pattern 1: Separate Volume Attachment Resource

**What:** Use `digitalocean_volume_attachment` as a separate resource rather than inline `volume_ids` on the droplet.
**When to use:** Always, when using `prevent_destroy` on the droplet or volume and when explicit dependency control is needed.
**Why:** Inline `volume_ids` causes Terraform to assume management of ALL volumes on the droplet, leading to drift. Separate attachment gives explicit dependency ordering and avoids the "volume attached, cannot be deleted" error on destroy.

**Example:**
```hcl
# Source: DigitalOcean Terraform provider docs
resource "digitalocean_volume" "data" {
  region                  = var.region
  name                    = "${var.project_name}-data"
  size                    = var.volume_size_gb
  initial_filesystem_type = "ext4"
  description             = "Persistent data volume for PostgreSQL and Odoo filestore"

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_droplet" "odoo" {
  image    = "ubuntu-24-04-x64"
  name     = "${var.project_name}-odoo"
  region   = var.region
  size     = var.droplet_size
  vpc_uuid = digitalocean_vpc.main.id
  ssh_keys = [local.ssh_key_id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_volume_attachment" "data" {
  droplet_id = digitalocean_droplet.odoo.id
  volume_id  = digitalocean_volume.data.id
}
```

### Pattern 2: Conditional SSH Key (Existing vs Upload)

**What:** Use a tfvars toggle to either reference an existing DO SSH key by name or upload a local public key file.
**When to use:** When operators may have pre-existing keys in their DO account.

**Example:**
```hcl
# Source: DigitalOcean Terraform provider docs (ssh_key resource + data source)
variable "use_existing_ssh_key" {
  description = "If true, look up existing key by name; if false, upload from local file"
  type        = bool
  default     = true
}

variable "ssh_key_name" {
  description = "Name of existing SSH key in DigitalOcean (when use_existing_ssh_key = true)"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to local public key file (when use_existing_ssh_key = false)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

data "digitalocean_ssh_key" "existing" {
  count = var.use_existing_ssh_key ? 1 : 0
  name  = var.ssh_key_name
}

resource "digitalocean_ssh_key" "uploaded" {
  count      = var.use_existing_ssh_key ? 0 : 1
  name       = "${var.project_name}-deploy-key"
  public_key = file(var.ssh_public_key_path)
}

locals {
  ssh_key_id = var.use_existing_ssh_key ? data.digitalocean_ssh_key.existing[0].id : digitalocean_ssh_key.uploaded[0].id
}
```

### Pattern 3: S3 Backend for DO Spaces

**What:** Configure Terraform S3 backend to use DigitalOcean Spaces as remote state store.
**When to use:** Always -- remote state is a locked decision.

**Example:**
```hcl
# Source: https://docs.digitalocean.com/products/spaces/reference/terraform-backend/
terraform {
  required_version = ">= 1.6.3"

  backend "s3" {
    endpoints = {
      s3 = "https://nyc3.digitaloceanspaces.com"
    }

    bucket                      = "my-project-tfstate"
    key                         = "terraform.tfstate"

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    region                      = "us-east-1"  # Required but unused; DO ignores this
  }
}
```

**Authentication via environment variables:**
```bash
export AWS_ACCESS_KEY_ID="<do_spaces_access_key>"
export AWS_SECRET_ACCESS_KEY="<do_spaces_secret_key>"
```

### Pattern 4: Remote-Exec SSH Verification

**What:** Minimal remote-exec provisioner that verifies SSH connectivity and volume mount.
**When to use:** Phase 1 only -- Phase 2 replaces with full provisioning scripts.

**Example:**
```hcl
# Source: HashiCorp Terraform provisioner docs + DO community patterns
resource "digitalocean_droplet" "odoo" {
  # ... resource arguments ...

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = self.ipv4_address
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'SSH connection verified'",
      "cloud-init status --wait || true",
      "lsblk | grep -q 'disk' && echo 'Block device detected'",
      "mount | grep '/mnt/' && echo 'Volume mount verified' || echo 'WARNING: Volume not yet mounted'"
    ]
  }
}
```

### Anti-Patterns to Avoid

- **Mixing volume_ids and volume_attachment:** Never use inline `volume_ids` on the droplet AND `digitalocean_volume_attachment` for the same droplet. This creates constant drift. Pick one approach.
- **Hardcoding the Spaces bucket in Terraform resources:** The state backend bucket must exist before `terraform init`. Do not try to manage it with Terraform -- it creates a chicken-and-egg problem.
- **Skipping prevent_destroy on production resources:** Without `lifecycle { prevent_destroy = true }`, an accidental `terraform destroy` deletes the droplet and volume with all data. This is a user-locked decision.
- **Committing terraform.tfvars with secrets:** Always gitignore `*.tfvars`; commit only `terraform.tfvars.example` with placeholder values.
- **Using reserved DO IP ranges for VPC:** DigitalOcean reserves `10.244.0.0/16`, `10.245.0.0/16`, `10.246.0.0/24`, and `10.229.0.0/16` globally, plus regional ranges (e.g., NYC3 uses `10.17.0.0/16`). Using these ranges causes silent networking failures.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Remote state storage | Custom state sync scripts | `backend "s3"` with DO Spaces | Terraform natively supports S3-compatible backends; custom sync risks state corruption |
| SSH key management | Manual key upload via API | `digitalocean_ssh_key` resource or `data.digitalocean_ssh_key` data source | Provider handles idempotency, state tracking, and cleanup |
| Firewall rules | Manual iptables/UFW in provisioner | `digitalocean_firewall` resource | Cloud firewall applies before droplet boot, is stateful, and survives droplet rebuilds |
| Volume formatting | Provisioner script to mkfs/mount | `initial_filesystem_type = "ext4"` on volume resource | DO pre-formats and auto-mounts volumes with specified filesystem |
| VPC creation | Manual API calls | `digitalocean_vpc` resource | Provider handles CIDR validation, region assignment, and resource association |

**Key insight:** The DigitalOcean Terraform provider handles most infrastructure concerns declaratively. The only manual step is the one-time Spaces bucket bootstrap -- everything else should be in HCL.

## Common Pitfalls

### Pitfall 1: Volume Cannot Be Deleted While Attached
**What goes wrong:** `terraform destroy` fails with "A volume that's attached to a Droplet cannot be deleted. Please detach it first before deleting."
**Why it happens:** Terraform tries to delete volume and droplet in parallel (or volume first) without detaching. This is a well-documented issue (GitHub issue #87 on the DO provider).
**How to avoid:** Use `digitalocean_volume_attachment` as a separate resource. Terraform's dependency graph then ensures: destroy attachment first, then volume and droplet. Combined with `prevent_destroy`, production data is protected.
**Warning signs:** `terraform plan` shows volume destruction before attachment destruction.

### Pitfall 2: SSH Connection Timeout on New Droplet
**What goes wrong:** `remote-exec` provisioner fails with SSH timeout because the droplet is not yet ready to accept connections.
**Why it happens:** The DO API reports the droplet as "active" before cloud-init finishes and SSH is fully ready. Default timeout may be too short.
**How to avoid:** Set `timeout = "2m"` in the connection block. Optionally add `cloud-init status --wait` as the first remote-exec command to block until initialization completes.
**Warning signs:** Intermittent first-apply failures that succeed on retry.

### Pitfall 3: Spaces Backend Auth Uses AWS_* Environment Variables
**What goes wrong:** `terraform init` fails with authentication errors because the operator set `DIGITALOCEAN_TOKEN` but not `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
**Why it happens:** The S3 backend uses AWS SDK authentication, not the DO provider token. These are separate credential sets: DO API token for the provider, Spaces access/secret keys for the backend.
**How to avoid:** Document clearly that TWO sets of credentials are needed: (1) `DIGITALOCEAN_TOKEN` for the provider and (2) `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` for the Spaces backend. Include this in the bootstrap runbook.
**Warning signs:** "Access Denied" or "Invalid credentials" errors during `terraform init` but not during `terraform plan`.

### Pitfall 4: VPC IP Range Conflicts with DO Reserved Ranges
**What goes wrong:** Droplet networking fails silently or VPC creation fails.
**Why it happens:** DigitalOcean reserves several `10.x.x.x/16` ranges for internal use. If you choose a CIDR that overlaps, networking breaks.
**How to avoid:** Use a safe range like `10.100.0.0/24` (well outside reserved ranges). Avoid the `10.17.x.x`, `10.48.x.x`, `10.244.x.x`, `10.245.x.x`, `10.246.x.x`, `10.229.x.x` blocks entirely.
**Warning signs:** Droplets created but cannot communicate over private network.

### Pitfall 5: Spaces Bucket Name Must Be Globally Unique
**What goes wrong:** Manual bucket creation fails with a naming conflict.
**Why it happens:** DO Spaces bucket names share a global namespace (like S3). Common names are taken.
**How to avoid:** Use a project-specific prefix, e.g., `odoo-prod-tfstate-<random>` or `<orgname>-odoo-tfstate`.
**Warning signs:** "Bucket name already in use" error during manual bootstrap step.

### Pitfall 6: Backend Configuration Cannot Use Variables
**What goes wrong:** Operator tries to use `var.region` or `var.bucket_name` in the `backend "s3"` block.
**Why it happens:** Terraform backend blocks are evaluated before any other configuration, so variables, locals, and data sources are not available.
**How to avoid:** Hardcode backend values in `backend.tf` or use `-backend-config` CLI flags during `terraform init` for partial configuration.
**Warning signs:** Syntax error during `terraform init` referencing variables in backend block.

## Code Examples

### Complete providers.tf
```hcl
# Source: https://docs.digitalocean.com/reference/terraform/getting-started/
terraform {
  required_version = ">= 1.6.3"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}
```

### Complete VPC + Firewall
```hcl
# Source: https://docs.digitalocean.com/reference/terraform/reference/resources/vpc/
# Source: https://docs.digitalocean.com/reference/terraform/reference/resources/firewall/
resource "digitalocean_vpc" "main" {
  name     = "${var.project_name}-vpc"
  region   = var.region
  ip_range = var.vpc_cidr  # e.g., "10.100.0.0/24"
}

resource "digitalocean_firewall" "main" {
  name        = "${var.project_name}-fw"
  droplet_ids = [digitalocean_droplet.odoo.id]

  # SSH -- restricted to operator IPs
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ssh_ips  # e.g., ["203.0.113.0/32"]
  }

  # HTTP
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound: allow all (needed for apt, Docker pulls, etc.)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
```

### Complete outputs.tf
```hcl
# Source: https://docs.digitalocean.com/reference/terraform/reference/resources/droplet/
output "droplet_ip" {
  description = "Public IPv4 address of the Odoo droplet"
  value       = digitalocean_droplet.odoo.ipv4_address
}

output "droplet_ip_private" {
  description = "Private IPv4 address within VPC"
  value       = digitalocean_droplet.odoo.ipv4_address_private
}

output "volume_mount_path" {
  description = "Mount path for the Block Storage Volume"
  value       = "/mnt/${digitalocean_volume.data.name}"
}

output "spaces_endpoint" {
  description = "DO Spaces endpoint URL for the state backend region"
  value       = "https://${var.region}.digitaloceanspaces.com"
}
```

### Recommended .gitignore for infra/
```gitignore
# Source: https://github.com/github/gitignore/blob/main/Terraform.gitignore
# Local .terraform directories
.terraform/

# .tfstate files
*.tfstate
*.tfstate.*

# Crash log files
crash.log
crash.*.log

# Exclude all .tfvars files (likely contain secrets)
*.tfvars
*.tfvars.json

# Override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Transient lock info
.terraform.tfstate.lock.info

# CLI configuration
.terraformrc
terraform.rc

# NOTE: .terraform.lock.hcl is COMMITTED (ensures reproducible provider versions)
```

### terraform.tfvars.example Template
```hcl
# DigitalOcean API Token
# Primary: export DIGITALOCEAN_TOKEN="your-api-token"
# Fallback: uncomment and set here
# do_token = "your-digitalocean-api-token"

# Project naming
project_name = "odoo-prod"

# Region (nyc1 or nyc3)
region = "nyc3"

# Droplet sizing
droplet_size = "s-2vcpu-4gb"

# Volume sizing (GB)
volume_size_gb = 25

# VPC CIDR
vpc_cidr = "10.100.0.0/24"

# SSH Configuration
use_existing_ssh_key = true
ssh_key_name         = "my-existing-key"
# ssh_public_key_path  = "~/.ssh/id_ed25519.pub"  # only when use_existing_ssh_key = false
ssh_private_key_path = "~/.ssh/id_ed25519"

# Firewall: IPs allowed to SSH (CIDR notation)
allowed_ssh_ips = ["0.0.0.0/0"]  # CHANGE THIS to your IP(s)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `backend "s3" { endpoint = "..." }` (single string) | `backend "s3" { endpoints = { s3 = "..." } }` (map) | Terraform 1.6.3 (2023) | Old `endpoint` syntax deprecated; must use `endpoints` map for S3-compatible backends |
| Chef/Puppet provisioners built into Terraform | Removed in Terraform 0.15.0 | 2021 | Only `file`, `local-exec`, `remote-exec` remain as built-in provisioners |
| `digitalocean_floating_ip` | `digitalocean_reserved_ip` | Provider v2.22.0 (2022) | Renamed; old resource deprecated. Not needed for Phase 1 but relevant if static IP is added later. |
| No `skip_s3_checksum` flag | `skip_s3_checksum = true` required | Terraform 1.6+ | Newer S3 backend requires this flag for non-AWS S3-compatible providers |

**Deprecated/outdated:**
- `endpoint` (singular) in S3 backend: replaced by `endpoints` map -- using old syntax causes init failure on Terraform >= 1.6.3
- `terraform_remote_state` data source for cross-project state: Not needed here (single project)
- Vendor provisioners (chef, puppet, habitat): Removed in 0.15.0; use generic provisioners or cloud-init

## Open Questions

1. **DO Volume Auto-Mount Path Convention**
   - What we know: DigitalOcean auto-mounts volumes with `initial_filesystem_type` set. The mount path follows the pattern `/mnt/<volume-name>`.
   - What's unclear: Whether the exact mount point is guaranteed to be `/mnt/<volume-name>` in all cases, or if it varies by OS image. The remote-exec verification step in Phase 1 will confirm this.
   - Recommendation: Use the remote-exec provisioner to verify the actual mount path and output it. Do not assume the path without verification.

2. **Terraform Provider Version Pinning: `~> 2.0` vs Tighter Constraint**
   - What we know: `~> 2.0` allows any 2.x release. The provider is at 2.76.0 and actively evolving.
   - What's unclear: Whether a major breaking change could land in a 2.x minor release (unlikely but provider is community-maintained).
   - Recommendation: Use `~> 2.0` for now (matches official DO getting-started docs). The `.terraform.lock.hcl` file pins the exact version used, preventing surprise upgrades. Can tighten later if needed.

3. **Spaces Bucket Region: nyc1 vs nyc3 for State Backend**
   - What we know: User wants region nyc1 or nyc3 for the droplet. Spaces is available in nyc3 but availability in nyc1 varies.
   - What's unclear: Whether nyc1 supports Spaces buckets or only nyc3.
   - Recommendation: Use nyc3 for both the Spaces bucket and the droplet region to keep everything co-located. Validate nyc1 Spaces availability if nyc1 is preferred.

## Sources

### Primary (HIGH confidence)
- [DigitalOcean Terraform Backend Docs](https://docs.digitalocean.com/products/spaces/reference/terraform-backend/) -- S3 backend configuration, skip flags, environment variables, Terraform >= 1.6.3 requirement
- [DigitalOcean Terraform Resources Reference](https://docs.digitalocean.com/reference/terraform/reference/resources/) -- All 80+ resource types for provider v2.76.0
- [DigitalOcean Firewall Resource](https://docs.digitalocean.com/reference/terraform/reference/resources/firewall/) -- Inbound/outbound rule configuration, port range syntax, droplet association
- [DigitalOcean Droplet Resource](https://docs.digitalocean.com/reference/terraform/reference/resources/droplet/) -- All arguments, exported attributes, volume_ids caveat
- [DigitalOcean Volume Resource](https://docs.digitalocean.com/reference/terraform/reference/resources/volume/) -- initial_filesystem_type, size, region, naming rules
- [DigitalOcean Volume Attachment Resource](https://docs.digitalocean.com/reference/terraform/reference/resources/volume_attachment/) -- Exclusive use warning (cannot mix with inline volume_ids)
- [DigitalOcean VPC Planning](https://docs.digitalocean.com/products/networking/vpc/concepts/plan-your-network/) -- Reserved IP ranges, CIDR limits (/16 to /28)
- [DigitalOcean Getting Started with Terraform](https://docs.digitalocean.com/reference/terraform/getting-started/) -- required_providers block, authentication pattern
- [GitHub: terraform-provider-digitalocean Releases](https://github.com/digitalocean/terraform-provider-digitalocean/releases) -- v2.76.0 released 2026-02-16
- [HashiCorp: Terraform Provisioners](https://developer.hashicorp.com/terraform/language/provisioners) -- "Last resort" guidance, connection block, security considerations
- [GitHub: Terraform.gitignore](https://github.com/github/gitignore/blob/main/Terraform.gitignore) -- Standard .gitignore template
- [HashiCorp: Terraform Releases](https://releases.hashicorp.com/terraform) -- v1.14.5 current stable (2026-02-11)

### Secondary (MEDIUM confidence)
- [DigitalOcean Community: How to Use Terraform with DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-use-terraform-with-digitalocean) -- End-to-end tutorial, connection block patterns
- [Spacelift: Terraform Files and Structure](https://spacelift.io/blog/terraform-files) -- Flat vs modular layout recommendations
- [Spacelift: Terraform .tfvars Best Practices](https://spacelift.io/blog/terraform-tfvars) -- tfvars.example pattern, sensitive variable handling
- [HashiCorp Discuss: Wait for Droplet Boot](https://discuss.hashicorp.com/t/how-to-wait-until-digitalocean-droplet-is-completely-booted-before-executing-futher-commands/3026) -- cloud-init status --wait pattern

### Tertiary (LOW confidence)
- [GitHub Issue #87: Volume Cannot Be Deleted While Attached](https://github.com/digitalocean/terraform-provider-digitalocean/issues/87) -- Confirms volume attachment ordering issue (historic but still relevant)
- [GitHub Issue #488: VPC Fails to Destroy](https://github.com/digitalocean/terraform-provider-digitalocean/issues/488) -- VPC destroy ordering with contained resources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Official DO docs confirm all provider resources, versions, and S3 backend configuration
- Architecture: HIGH -- Flat layout and all resource patterns verified against official documentation
- Pitfalls: HIGH -- Volume attachment, SSH timeout, and backend auth issues confirmed via official docs and GitHub issues

**Research date:** 2026-02-21
**Valid until:** 2026-03-21 (30 days -- stable ecosystem, provider release cycle is ~weekly for minor fixes)
