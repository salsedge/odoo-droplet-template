# Handoff — odoo-droplet-template

**Date:** 2026-03-31
**Branch:** main
**Origin:** Forked from `salsedge/odoo-19.x-build` at tag `v1.0`

## What Happened

Created this repo as a template for deploying Odoo Community 19.x on DigitalOcean. The codebase is an exact copy of the Loodon production instance (`odoo-19.x-build`) which remains the DR/instance repo for that deployment.

## Goal

Turn this from a single-instance deployment into a reusable template that can stamp out new Odoo instances for different clients/domains.

## What Needs to Happen

- Extract Loodon-specific values into variables or `.example` files:
  - Domain names (`portal.loodon.com`, `odoo.loodon.com`)
  - Terraform resource names (`loodon-prod-01-odoo`, VPC, volume, firewall names)
  - Database name (`loodon-01`) and user (`loomin`)
  - DO region, droplet size, volume size
  - SSH key fingerprint
  - OdooKit team-members config
- Add a bootstrap mechanism (Makefile target or setup script) that:
  - Prompts for or reads instance config (domain, project name, region, etc.)
  - Generates `.env`, `terraform.tfvars`, `odoo.conf`, Nginx configs from templates
  - Initializes Terraform backend (new Spaces bucket per instance)
- Remove Loodon-specific planning artifacts (`.planning/phases/`, STATE.md) — keep REQUIREMENTS.md and ROADMAP.md as reference
- Remove or generalize docs that reference Loodon specifically
- Update CLAUDE.md for the template context
- Consider: should each new instance get its own repo (generated from this template), or use Terraform workspaces within this repo?

## Key Decisions Already Made

- `odoo-19.x-build` stays frozen as Loodon's instance/DR repo
- This repo diverges independently — no need to keep in sync
- Architecture stays single-droplet (no K8s, no Swarm)
- Nginx on host, Docker `iptables: false`, UFW as firewall — all carry forward

## Reference

- Source repo: https://github.com/salsedge/odoo-19.x-build (tagged v1.0)
- Live instance: `45.55.164.120` / `loodon-prod-01-odoo`
- CRM buildout: `../ubop-lite/`

<!-- handoff:scope last_commit=f036580 timestamp=2026-03-31T06:14:52Z -->
