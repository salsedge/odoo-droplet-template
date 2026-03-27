# Odoo Production Monitoring -- Icinga2 Integration Guide

Two custom Icinga2 check plugins (Docker container health and PostgreSQL metrics) and parameterised service definition templates for integrating the Odoo production host with an existing Icinga2 master.

This guide covers plugin deployment on the agent host and service definition import on the master. After following these steps, the Icinga2 master will schedule and evaluate two custom checks -- `docker-stack` and `postgres-health` -- executed locally on the Odoo agent via `command_endpoint`.

## Architecture Overview

- The Icinga2 master schedules checks via `command_endpoint` -- it tells the agent **what** to run.
- The agent executes plugins locally on the Odoo host, accessing Docker directly.
- `check_docker_stack` queries the Docker daemon via `docker inspect`.
- `check_postgres_health` runs SQL queries via `docker exec` into the PostgreSQL container.

```
                         TLS (port 5665)
  Icinga2 Master  ─────────────────────────>  Icinga2 Agent (Odoo host)
                                                    │
                                                    ├── check_docker_stack
                                                    │       └── docker inspect → odoo-app, odoo-db
                                                    │
                                                    └── check_postgres_health
                                                            └── docker exec → psql (inside odoo-db)
```

## Prerequisites

Before deploying the custom plugins and service definitions, the following must already be in place:

1. **Icinga2 agent installed and registered with master** (MON-01)
   Handled by the Icinga2 master project's agent provisioning workflow. The agent must have a valid certificate and be communicating with the master over TLS.

2. **Standard system resource checks deployed** (MON-04)
   Handled by the Icinga2 master project. Includes `check_cpu`, `check_mem`, `check_disk`, and `check_load`. These are NOT part of this package.

3. **Docker CE running on the Odoo host**
   The Odoo stack (odoo-app and odoo-db containers) must be running.

4. **nagios user in docker group**
   The Icinga2 agent runs plugins as the `nagios` user, which needs Docker socket access:
   ```bash
   sudo usermod -aG docker nagios
   sudo systemctl restart icinga2
   ```

> **Note:** Agent installation, registration, and system resource checks are NOT part of this package. They are deployed by the Icinga2 master project's agent provisioning workflow.

## Directory Structure

```
monitoring/
  plugins/
    check_docker_stack          Docker container health check plugin (bash)
    check_postgres_health       PostgreSQL metrics check plugin (bash)
  icinga2/
    commands.conf               CheckCommand definitions (deploy to global-templates)
    services.conf               Service apply rules + ServiceGroup (deploy to master zone)
    notifications.conf          Notification rules using built-in mail commands (deploy to master zone)
  README.md                     This integration guide
```

## Plugin Deployment (on Odoo Agent Host)

Copy the plugins to the custom plugin directory on the agent host and set permissions:

```bash
sudo mkdir -p /usr/lib/nagios/plugins/custom
sudo cp monitoring/plugins/check_docker_stack /usr/lib/nagios/plugins/custom/
sudo cp monitoring/plugins/check_postgres_health /usr/lib/nagios/plugins/custom/
sudo chmod 755 /usr/lib/nagios/plugins/custom/check_*
sudo chown root:root /usr/lib/nagios/plugins/custom/check_*
```

Verify the plugins are accessible by the nagios user:

```bash
sudo -u nagios /usr/lib/nagios/plugins/custom/check_docker_stack --help
sudo -u nagios /usr/lib/nagios/plugins/custom/check_postgres_health --help
```

If you get "permission denied" on Docker commands:

```bash
sudo usermod -aG docker nagios
sudo systemctl restart icinga2
```

Then re-test. Group membership changes require a service restart to take effect.

## Service Definition Deployment (on Icinga2 Master)

### Step 1: Deploy CheckCommand definitions

Copy to the global-templates zone so commands are synced to all agents:

```bash
sudo cp monitoring/icinga2/commands.conf /etc/icinga2/zones.d/global-templates/odoo-commands.conf
```

### Step 2: Deploy Service and Notification definitions

Copy to the master zone:

```bash
sudo cp monitoring/icinga2/services.conf /etc/icinga2/zones.d/master/odoo-services.conf
sudo cp monitoring/icinga2/notifications.conf /etc/icinga2/zones.d/master/odoo-notifications.conf
```

### Step 3: Edit placeholders

Open each file and replace the placeholder values:

| File | Placeholder | Replace With |
|------|-------------|--------------|
| `commands.conf` | `CustomPluginDir` path | Agent plugin directory (default `/usr/lib/nagios/plugins/custom`) |
| `services.conf` | `DROPLET_IP_PLACEHOLDER` | Odoo droplet IP address |
| `services.conf` | `agent_endpoint` value | Agent NodeName (from `icinga2 node wizard`) |
| `notifications.conf` | `ADMIN_EMAIL_PLACEHOLDER` | Alert recipient email address |

### Step 4: Configure the host object

Ensure the Odoo host object has the required custom variables. Either add them to your existing host definition or uncomment the example in `odoo-services.conf`:

```
vars.odoo_host = true
vars.agent_endpoint = "odoo-prod"    // Must match the agent's NodeName
```

### Step 5: Validate configuration

```bash
icinga2 daemon -C
```

Fix any syntax errors before reloading.

### Step 6: Reload Icinga2

```bash
sudo systemctl reload icinga2
```

The two new services (`docker-stack` and `postgres-health`) should appear in the Icinga Web 2 dashboard under the `odoo-production` service group within one check interval (5 minutes).

## Check Details

### docker-stack

Monitors all Odoo Docker containers for running state, health status, and restart counts.

| Metric | What It Checks | Default Warning | Default Critical |
|--------|---------------|-----------------|------------------|
| Running state | Container is running (`docker inspect .State.Running`) | -- | Not running |
| Health status | Docker healthcheck result (`.State.Health.Status`) | -- | Unhealthy |
| Restart count | Number of container restarts (`.RestartCount`) | >= 2 | >= 5 |

**Containers monitored:** `odoo-app`, `odoo-db` (configurable via `--containers`)

**Configurable arguments:**

| Argument | Icinga2 Variable | Default | Description |
|----------|-----------------|---------|-------------|
| `--containers` | `docker_stack_containers` | `odoo-app,odoo-db` | Comma-separated container names |
| `--warn-restarts` | `docker_stack_warn_restarts` | `2` | Restart count warning threshold |
| `--crit-restarts` | `docker_stack_crit_restarts` | `5` | Restart count critical threshold |

### postgres-health

Monitors PostgreSQL database metrics via `docker exec` into the database container.

| Metric | What It Checks | Default Warning | Default Critical |
|--------|---------------|-----------------|------------------|
| Connections | Active connection count (`pg_stat_activity`) | >= 35 | >= 45 |
| Database size | Size in bytes (`pg_database_size()`) | >= 5 GB | >= 10 GB |
| Query latency | `SELECT 1` round-trip time (ms) | >= 300 ms | >= 1000 ms |
| Cache hit ratio | Buffer cache effectiveness (`pg_stat_database`) | <= 90% | <= 80% |

**Note:** Query latency includes `docker exec` overhead (~20-50ms). Thresholds account for this -- do not lower them to typical bare-metal psql values.

**Configurable arguments:**

| Argument | Icinga2 Variable | Default | Description |
|----------|-----------------|---------|-------------|
| `--container` | `postgres_health_container` | `odoo-db` | PostgreSQL container name |
| `--pg-user` | `postgres_health_user` | `odoo` | PostgreSQL user |
| `--pg-db` | `postgres_health_db` | `odoo` | PostgreSQL database |
| `--warn-conn` | `postgres_health_warn_conn` | `35` | Connection warning (of max 50) |
| `--crit-conn` | `postgres_health_crit_conn` | `45` | Connection critical (of max 50) |
| `--warn-size` | `postgres_health_warn_size` | `5368709120` | Size warning (5 GB in bytes) |
| `--crit-size` | `postgres_health_crit_size` | `10737418240` | Size critical (10 GB in bytes) |
| `--warn-latency` | `postgres_health_warn_latency` | `300` | Latency warning (ms, includes ~200-300ms docker exec overhead) |
| `--crit-latency` | `postgres_health_crit_latency` | `1000` | Latency critical (ms) |
| `--warn-cache` | `postgres_health_warn_cache` | `90` | Cache hit warning (%, below = warn) |
| `--crit-cache` | `postgres_health_crit_cache` | `80` | Cache hit critical (%, below = crit) |

## Threshold Tuning

Override default thresholds via Icinga2 custom variables on the host or service object. Host-level vars propagate to all services on that host.

**Example: Lower connection warning on a specific host:**

```
// In your host object definition
object Host "odoo-prod" {
  // ...existing config...
  vars.postgres_health_warn_conn = 25
  vars.postgres_health_crit_conn = 40
}
```

**Example: Adjust restart thresholds for a host that restarts frequently during maintenance:**

```
// In your host object definition
vars.docker_stack_warn_restarts = 5
vars.docker_stack_crit_restarts = 10
```

**Example: Override at the service level (applies only to that service):**

```
// In a service apply rule or object
vars.postgres_health_warn_size = 10737418240    // 10 GB warning
vars.postgres_health_crit_size = 21474836480    // 20 GB critical
```

The Icinga2 variable resolution order is: service vars > host vars > command defaults.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| UNKNOWN: docker command not found | Docker CLI not in PATH for nagios user | Verify Docker is installed; check `which docker` as nagios user |
| UNKNOWN: permission denied | nagios user not in docker group | `sudo usermod -aG docker nagios && sudo systemctl restart icinga2` |
| UNKNOWN: container not found | Wrong container name | Check `docker ps --format '{{.Names}}'` and update `--containers` or `--container` argument |
| UNKNOWN: plugin not found | Wrong plugin path or missing file | Verify plugin exists at `CustomPluginDir` path; check `ls -la /usr/lib/nagios/plugins/custom/` |
| CRITICAL but container looks healthy | Stale Docker state after daemon restart | Run `docker inspect <container>` manually to verify; restart the container if state is inconsistent |
| Latency always 200-300ms even when idle | Normal docker exec overhead on 2-vCPU droplet | This is expected behaviour; do not lower `--warn-latency` below 300ms |
| Cache hit ratio UNKNOWN after restart | No block reads yet on fresh database | Treat as transient; ratio stabilises after normal query activity |
| Perfdata not graphing | Label format issue or graphing backend not configured | Verify perfdata labels contain no spaces; check Icinga2 PerfdataWriter or Graphite/InfluxDB integration |
| Service not appearing in dashboard | Missing `vars.odoo_host = true` on host | Add the custom variable to the host object and reload Icinga2 |
| Check runs on master instead of agent | Missing or wrong `command_endpoint` | Verify `vars.agent_endpoint` matches the agent's NodeName exactly |

## Performance Data

Both plugins output Nagios-standard perfdata compatible with Graphite, InfluxDB, and PNP4Nagios.

### docker-stack perfdata

| Label | Unit | Description | Min | Max |
|-------|------|-------------|-----|-----|
| `odoo-app_restarts` | counter | Restart count for odoo-app container | 0 | -- |
| `odoo-db_restarts` | counter | Restart count for odoo-db container | 0 | -- |

### postgres-health perfdata

| Label | Unit | Description | Min | Max |
|-------|------|-------------|-----|-----|
| `connections` | count | Active PostgreSQL connections | 0 | 50 |
| `db_size` | bytes (B) | Database size on disk | 0 | -- |
| `query_latency` | milliseconds (ms) | SELECT 1 round-trip including docker exec overhead | 0 | -- |
| `cache_hit_ratio` | percent (%) | Buffer cache hit ratio | 0 | 100 |

All perfdata follows the format `label=value[UOM];warn;crit;min;max` as defined by the Nagios Plugin API. Labels use underscores (no spaces) to ensure correct parsing.

---

*Monitoring package for Odoo 19.x Production Build*
*Requirements: MON-01 (agent, external), MON-02 (Docker check), MON-03 (PG check), MON-04 (system checks, external), MON-05 (service definitions)*
