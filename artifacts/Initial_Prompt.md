**Situation**
You are deploying Odoo Community edition (preferred) or Enterprise as a containerized application on a DigitalOcean Ubuntu droplet that requires enterprise-grade security hardening and comprehensive monitoring integration. The deployment uses Docker containers to enable independent scaling of PostgreSQL and Odoo components. The entire infrastructure must operate behind a WireGuard VPN droplet for additional network security, with monitoring handled by an existing Icinga2 master server using agent-based checks. The deployment must follow PCI-DSS compliance requirements and support basic CRM and project management modules for 10 users. The infrastructure provisioning and configuration should leverage Infrastructure as Code (IaC) tools to ensure reproducibility, version control, and automated deployment capabilities.

**Task**
The assistant should create a complete, production-ready containerized deployment guide that includes:

1. Infrastructure as Code implementation using Terraform (primary) or Pulumi (alternative) for DigitalOcean resource provisioning (droplets, networking, volumes, VPC)
2. IaC modules for automated Ubuntu droplet creation, Docker and Docker Compose installation, and network configuration
3. Full system hardening implementation (UFW firewall rules, SSH hardening, fail2ban, automatic security updates, file permissions, and kernel parameters following PCI-DSS baseline) codified in IaC provisioners or configuration management
4. Containerized Odoo Community (or Enterprise if specified) deployment with separate PostgreSQL container to enable independent scaling
5. Docker security hardening (container isolation, resource limits, non-root users, image scanning) defined in IaC-managed Docker Compose files
6. Odoo application-level security configuration and performance optimization for 10-user CRM/project management workload
7. WireGuard VPN droplet configuration to front the containerized Odoo instance, provisioned and configured via IaC
8. Icinga2 agent installation and configuration to connect to the existing Icinga2 master server, automated through IaC provisioners
9. Custom monitoring checks for Odoo containers, PostgreSQL container, Docker daemon, system resources, and security events
10. Container orchestration strategy allowing PostgreSQL and Odoo to scale independently
11. Complete IaC configuration files (Terraform .tf files or Pulumi code) alongside bash scripts for automated deployment, hardening, and container management
12. Network architecture diagram showing the WireGuard-Docker-Odoo-Icinga2 topology with IaC-managed resources
13. IaC state management strategy and remote backend configuration for team collaboration

**Objective**
Deliver a secure, monitored, scalable, and production-ready containerized Odoo deployment that follows PCI-DSS compliance requirements and security best practices, minimizes attack surface through VPN isolation and container segmentation, enables independent scaling of database and application tiers, provides comprehensive visibility through Icinga2 monitoring integration, and ensures infrastructure reproducibility and version control through Infrastructure as Code implementation.

**Knowledge**
- Target platform: DigitalOcean Ubuntu 22.04 LTS or 24.04 LTS droplet
- Odoo version: Latest stable Community edition with basic CRM and project management modules
- Expected load: 10 concurrent users with moderate database growth
- Existing infrastructure: Operational Icinga2 master server (you will provide existing Icinga2 service definitions for web apps)
- Network architecture: WireGuard droplet acts as gateway, containerized Odoo and PostgreSQL operate in private network with Docker networking
- Security requirements: PCI-DSS compliant baseline with defense-in-depth approach including fail2ban, UFW, SSH hardening, and VPN isolation
- Containerization: Docker with Docker Compose for orchestration, separate containers for Odoo and PostgreSQL to enable independent scaling
- Monitoring scope: Container health, system health, application availability, database performance, security events
- IaC tooling: Terraform (preferred) with DigitalOcean provider, or Pulumi as alternative with TypeScript/Python examples
- IaC requirements: Modular structure, reusable components, environment separation (dev/staging/prod), state management with remote backend (DigitalOcean Spaces or Terraform Cloud)

The assistant should provide:
- Terraform configuration files organized in modules (networking, compute, security, monitoring) or equivalent Pulumi project structure
- DigitalOcean provider configuration with API token management and version pinning
- Resource definitions for droplets (Odoo/PostgreSQL container host, WireGuard gateway), VPC, firewalls, volumes, and load balancers (if horizontal scaling)
- IaC provisioners (remote-exec, file, or configuration management tool integration) for Docker installation and initial system setup
- Docker Compose configuration files managed as IaC templates with variable interpolation for environment-specific values
- Modular bash scripts for Docker installation, container deployment, and system hardening that can be executed independently or as a complete pipeline, triggered by IaC provisioners
- Dockerfile configurations for Odoo with security hardening (non-root user, minimal base image, vulnerability scanning)
- Docker networking configuration to isolate containers while maintaining WireGuard connectivity, defined in IaC-managed Compose files
- Detailed configuration files for UFW/iptables, WireGuard, Docker daemon, Odoo, PostgreSQL, and Icinga2 agent, templated and deployed via IaC
- PCI-DSS focused security hardening checklist covering fail2ban rules, SSH configuration, firewall policies, and VPN enforcement, implemented through IaC
- Icinga2 service definitions for monitoring Docker containers, including the user-provided web app monitoring templates adapted for containerized Odoo
- Container scaling procedures for both PostgreSQL and Odoo components with IaC modifications for resource adjustments
- Docker volume management for persistent data (PostgreSQL data, Odoo filestore) with DigitalOcean Volumes attached via IaC
- Rollback procedures using IaC state management and troubleshooting steps for containerized environments
- Documentation on connecting the Icinga2 agent to the master using certificates or API keys, automated through IaC provisioners
- Performance tuning recommendations for PostgreSQL container and Odoo container based on 10-user workload and droplet size
- Container backup strategies and disaster recovery considerations with IaC-managed backup resources
- SSL/TLS certificate setup (Let's Encrypt) with automatic renewal in containerized environment
- Resource limits and health checks for each container
- IaC variable files (.tfvars or Pulumi config) for environment-specific customization (IP ranges, droplet sizes, SSH keys)
- IaC outputs for critical information (droplet IPs, VPN endpoints, connection strings)
- CI/CD integration examples for automated IaC deployment (GitHub Actions, GitLab CI)

When X scenario occurs, do Y:
- When Odoo Community container fails to start, provide Enterprise container alternative with license configuration and volume mounting steps
- When WireGuard connectivity issues arise, include diagnostic commands for container network inspection and common resolution steps
- When Icinga2 agent cannot connect to master, provide certificate troubleshooting and manual registration process
- When PostgreSQL container performance is suboptimal, include tuning parameters and container resource allocation based on available RAM
- When scaling is needed, provide step-by-step instructions for scaling PostgreSQL container (vertical with IaC droplet resizing) and Odoo container (horizontal with load balancing considerations and IaC resource additions)
- When container health checks fail, provide debugging procedures using docker logs and docker inspect commands
- When IaC state conflicts occur, provide state management commands (terraform state, pulumi stack) and resolution procedures
- When infrastructure drift is detected, provide IaC refresh and reconciliation steps

The assistant should structure the output as:
1. Architecture Overview (network and container topology diagram in ASCII or description, including IaC-managed resources)
2. Prerequisites and Assumptions (including IaC tool installation and DigitalOcean API access)
3. Phase 1: IaC Project Structure and Setup (Terraform/Pulumi initialization, provider configuration, remote state backend)
4. Phase 2: IaC Networking Module (VPC, firewall rules, WireGuard gateway droplet)
5. Phase 3: IaC Compute Module (Odoo/PostgreSQL container host droplet, volume attachments, SSH key management)
6. Phase 4: Base System Hardening Script (PCI-DSS focused: fail2ban, UFW, SSH, updates) triggered by IaC provisioners
7. Phase 5: Docker Installation and Security Configuration Script deployed via IaC
8. Phase 6: Docker Compose Configuration for Odoo and PostgreSQL (separate scalable services) managed as IaC templates
9. Phase 7: Container Deployment and Initialization Script executed through IaC provisioners
10. Phase 8: WireGuard Configuration Script deployed via IaC
11. Phase 9: Icinga2 Agent Setup Script with Container Monitoring automated through IaC
12. Configuration Files (separate sections for each service: Docker daemon, Compose, UFW, WireGuard, Icinga2, all IaC-managed)
13. Monitoring Checks and Service Definitions (incorporating user-provided web app templates for containerized environment)
14. Container Scaling Procedures (PostgreSQL vertical scaling with IaC, Odoo horizontal scaling with IaC)
15. IaC Operations Guide (apply, plan, destroy, state management, workspace/stack management)
16. Post-Deployment Verification Steps
17. Container Management and Operations Guide (backup, updates, rollback)
18. IaC Best Practices and Security Considerations (secrets management, state encryption, access control)

Use explicit commands, file paths, configuration parameters, Docker-specific syntax, and IaC resource definitions. Avoid generic placeholders—provide working examples with clear instructions on what needs customization (IP addresses, passwords, hostnames, container resource limits, volume paths, IaC variables). All scripts should be idempotent and include error handling for production reliability. IaC configurations should follow best practices for modularity, reusability, and security (secrets management, state encryption).