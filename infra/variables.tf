# -----------------------------------------------------------------------------
# Variable Declarations
# All configurable values for the Odoo production infrastructure.
# Secrets should be passed via environment variables (see terraform.tfvars.example).
# -----------------------------------------------------------------------------

variable "do_token" {
  description = "DigitalOcean API token. Prefer env var: export DIGITALOCEAN_TOKEN=\"...\""
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Prefix for all resource names (droplet, VPC, firewall, volume)"
  type        = string
  default     = "odoo-prod"
}

variable "region" {
  description = "DigitalOcean region for all resources (e.g., nyc3, nyc1)"
  type        = string
  default     = "nyc3"
}

variable "droplet_size" {
  description = "Droplet size slug (e.g., s-2vcpu-4gb for 2 vCPU / 4 GB RAM)"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "volume_size_gb" {
  description = "Block Storage Volume size in GB for PostgreSQL data and Odoo filestore"
  type        = number
  default     = 25
}

variable "vpc_cidr" {
  description = "VPC IP range in CIDR notation. Use a safe range outside DO reserved blocks (e.g., 10.100.0.0/24)"
  type        = string
  default     = "10.100.0.0/24"
}

variable "use_existing_ssh_key" {
  description = "If true, look up an existing SSH key in DO by name. If false, upload from a local public key file."
  type        = bool
  default     = true
}

variable "ssh_key_name" {
  description = "Name of an existing SSH key in your DigitalOcean account (used when use_existing_ssh_key = true)"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to local SSH public key file (used when use_existing_ssh_key = false)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Path to local SSH private key file for remote-exec provisioner connections"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "allowed_ssh_ips" {
  description = "CIDR blocks allowed to SSH into the droplet. Restrict to your IP(s) for security."
  type        = list(string)
}
