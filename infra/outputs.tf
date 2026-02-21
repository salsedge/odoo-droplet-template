# -----------------------------------------------------------------------------
# Output Values
# Critical infrastructure values exposed after terraform apply.
# IAC-08: Droplet IP, volume mount path, and Spaces endpoint are required.
# Additional outputs provided for operational reference and cross-phase usage.
# -----------------------------------------------------------------------------

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

output "droplet_name" {
  description = "Name of the Odoo droplet"
  value       = digitalocean_droplet.odoo.name
}

output "volume_name" {
  description = "Name of the Block Storage Volume"
  value       = digitalocean_volume.data.name
}

output "vpc_id" {
  description = "VPC ID for reference by subsequent phases"
  value       = digitalocean_vpc.main.id
}
