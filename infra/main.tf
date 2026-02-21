# -----------------------------------------------------------------------------
# Main Resource Definitions
# All DigitalOcean infrastructure for the Odoo production environment.
# Resources are ordered by dependency: SSH key -> VPC -> Volume -> Droplet ->
# Volume Attachment -> Firewall
# -----------------------------------------------------------------------------

# =============================================================================
# SSH Key Logic (conditional: existing lookup vs local upload)
# =============================================================================

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

# =============================================================================
# IAC-01: VPC with private networking
# =============================================================================

resource "digitalocean_vpc" "main" {
  name     = "${var.project_name}-vpc"
  region   = var.region
  ip_range = var.vpc_cidr
}

# =============================================================================
# IAC-04: Block Storage Volume for persistent data (PostgreSQL + Odoo filestore)
# =============================================================================

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

# =============================================================================
# IAC-03: Odoo application droplet (Ubuntu 24.04 LTS)
# IAC-07: Remote-exec provisioner for SSH verification
# =============================================================================

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

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = self.ipv4_address
    timeout     = "2m"
  }

  # Minimal Phase 1 provisioner: verify SSH connectivity and block device detection.
  # NOTE: The volume may not be mounted yet because volume_attachment runs after the
  # droplet. This is expected -- full mount verification happens after attachment.
  provisioner "remote-exec" {
    inline = [
      "echo 'SSH connection verified'",
      "cloud-init status --wait || true",
      "lsblk | grep -q 'disk' && echo 'Block device detected'",
      "mount | grep '/mnt/' && echo 'Volume mount verified' || echo 'WARNING: Volume not yet mounted - will be available after volume_attachment'"
    ]
  }
}

# =============================================================================
# IAC-04: Volume Attachment (separate resource for correct destroy ordering)
# NOTE: Do NOT use inline volume_ids on the droplet -- see RESEARCH.md Pattern 1
# =============================================================================

resource "digitalocean_volume_attachment" "data" {
  droplet_id = digitalocean_droplet.odoo.id
  volume_id  = digitalocean_volume.data.id
}

# =============================================================================
# IAC-02: Cloud Firewall (SSH restricted, HTTP/HTTPS open)
# =============================================================================

resource "digitalocean_firewall" "main" {
  name        = "${var.project_name}-fw"
  droplet_ids = [digitalocean_droplet.odoo.id]

  # SSH -- restricted to operator IPs
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ssh_ips
  }

  # HTTP -- public access
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS -- public access
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
