# Phase 6: Monitoring - Research

**Researched:** 2026-03-22
**Domain:** Icinga2 custom check plugins, Nagios plugin API, Docker container monitoring, PostgreSQL health checks
**Confidence:** HIGH

## Summary

Phase 6 delivers two custom Icinga2 check plugins (Docker container health and PostgreSQL metrics) plus parameterized service definition templates for the Icinga2 master admin. The scope is narrow because the Icinga2 master project handles agent installation (MON-01) and standard system resource checks (MON-04) -- this phase only covers MON-02, MON-03, and MON-05.

Both plugins follow the Nagios Plugin API: exit codes 0/1/2/3, single-line status output, perfdata after pipe. The Docker check uses `docker inspect --format` to query container state, health status, and restart counts. The PostgreSQL check uses `docker exec` + `psql` to query `pg_stat_database`, `pg_database_size()`, and `SELECT 1` latency -- no host-level PG client required. Service definitions are Icinga2 DSL templates that the master admin parameterizes with host names, zones, and notification groups.

**Primary recommendation:** Write both plugins in bash (no external dependencies, matches project script conventions), use `docker inspect` Go templates for Docker state, and `docker exec -i odoo-db psql` for PostgreSQL metrics. Deliver service definitions as documented `.conf` templates with placeholder variables the master admin fills in.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Two custom check plugins: one for Docker stack, one for PostgreSQL
- Docker check is a single plugin monitoring all containers (odoo + postgres) -- not per-container
- PostgreSQL check is a single plugin reporting all PG metrics in one invocation
- Plugins follow standard Nagios plugin conventions: exit codes 0/1/2/3 (OK/WARN/CRIT/UNKNOWN), perfdata after `|`, one-line status output
- Plugins live in `monitoring/` directory (top-level, separate from `config/`)
- PG check authenticates via `docker exec` + `psql` inside the PostgreSQL container -- no host-level PG client needed
- Docker alert thresholds: Critical at container not running, unhealthy Docker health status, or restart count >= 5; Warning at restart count >= 2
- Docker check uses Docker health status (healthcheck configured in compose) -- unhealthy containers alert even if technically running
- PostgreSQL thresholds: connections warn 35/crit 45 (of max_connections=50); DB size warn 5GB/crit 10GB; cache hit ratio warn <90%/crit <80%
- Service definitions: parameterized templates with README documentation -- not ready-to-drop .conf files
- Master admin customizes host names, zones, and notification groups from templates
- 5-minute check interval for all custom checks
- Include example notification templates (email) that the admin can enable/customize
- Checks grouped into an 'odoo-production' service group for dashboard organization

### Claude's Discretion
- Plugin language choice (bash vs python) per check -- pick the best fit
- Query latency warn/crit thresholds
- DB size warn/crit values (5GB/10GB suggested but can adjust if more appropriate)
- Exact perfdata output format details
- Script error handling patterns
- Template parameterization approach

### Deferred Ideas (OUT OF SCOPE)
- AMON-01 (security event monitoring -- failed logins, firewall blocks) -- advanced monitoring, future phase
- AMON-02 (backup success/failure alerting via Icinga2) -- could extend the backup check plugin later
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MON-01 | Icinga2 agent installed on host and registered with existing Icinga2 master | **Handled by Icinga2 master project** -- master install script covers agent installation and registration. Out of scope for this phase. |
| MON-02 | Custom check monitors Docker container health (running, restart count, resource usage) | Docker check plugin using `docker inspect --format` for State.Running, State.Health.Status, RestartCount. Nagios perfdata for restart counts. See Architecture Patterns section. |
| MON-03 | Custom check monitors PostgreSQL (connections, database size, query latency) | PostgreSQL check plugin using `docker exec` + `psql` to query pg_stat_database, pg_database_size(), SELECT 1 timing, and cache hit ratio. See Architecture Patterns section. |
| MON-04 | System resource checks (CPU, memory, disk usage, load average) | **Handled by Icinga2 master project** -- standard monitoring plugins (check_cpu, check_mem, check_disk, check_load) deployed by master's agent install. Out of scope for this phase. |
| MON-05 | Icinga2 service definitions provided for integration with master | Parameterized Icinga2 DSL templates: CheckCommand objects, Service apply rules with command_endpoint, ServiceGroup, and Notification apply rules. See Service Definition Templates section. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 5.x (Ubuntu 24.04 default) | Check plugin scripting | Matches all existing project scripts, no extra dependencies, Nagios plugin convention |
| docker inspect | Docker CE (already installed) | Container state queries | Native Docker CLI, Go template format for structured output |
| psql | PostgreSQL 18 (inside container) | Database metric queries | Already available in PG container, no host-level install needed |
| Icinga2 DSL | Icinga2 2.14.x | Service definition templates | Native Icinga2 configuration language |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `date` + `bc` | coreutils | Timing calculations | Query latency measurement (millisecond precision via `date +%s%N`) |
| `jq` | apt package | JSON parsing (optional) | Only if Docker inspect JSON output needs complex parsing -- avoid if Go templates suffice |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bash plugins | Python plugins | Python adds dependency management, but the checks are simple enough that bash with `docker inspect --format` and `psql -t -A -c` is cleaner and dependency-free |
| docker inspect --format | docker inspect + jq | Go templates are sufficient for the fields we need; jq adds a dependency |
| docker exec psql | Host-level psql client | Host-level client would need separate install, credentials management, and network access to the internal backend Docker network. docker exec keeps everything Docker-only |
| check_postgres (Perl) | Custom bash plugin | check_postgres requires Perl + host psql client + network route to PG. Overkill for 4 metrics when direct SQL queries are trivial |

**Recommendation:** Bash for both plugins. The Docker check is pure `docker inspect` calls -- no advantage to Python. The PostgreSQL check runs 4 simple SQL queries via `docker exec` -- simpler in bash than managing a Python environment.

## Architecture Patterns

### Recommended Directory Structure
```
monitoring/
  plugins/
    check_docker_stack      # Docker container health check plugin
    check_postgres_health   # PostgreSQL metrics check plugin
  icinga2/
    commands.conf           # CheckCommand definitions (goes in global-templates zone)
    services.conf           # Service + ServiceGroup definitions (goes in master zone)
    notifications.conf      # Notification apply rules + email examples
  README.md                 # Integration guide for Icinga2 master admin
```

### Pattern 1: Nagios Plugin Output Format
**What:** Standard output format all Icinga2/Nagios plugins must follow
**When to use:** Every check plugin
**Specification (from Nagios Plugin API):**

```
STATUS_TEXT | 'label1'=value[UOM];[warn];[crit];[min];[max] 'label2'=value...
```

Exit codes:
- `0` = OK
- `1` = WARNING
- `2` = CRITICAL
- `3` = UNKNOWN

Performance data format: `label=value[UOM];warn;crit;min;max`

Units of measure (UOM): `s` (seconds), `%` (percentage), `B`/`KB`/`MB`/`GB`/`TB` (bytes), `c` (counter).

Output limited to 4KB by Nagios core. First line goes to `$SERVICEOUTPUT$`, perfdata goes to `$SERVICEPERFDATA$`.

Source: [Nagios Plugin API](https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/3/en/pluginapi.html)

### Pattern 2: Docker Container Health Check Plugin
**What:** Single plugin that checks both odoo-app and odoo-db containers
**Logic flow:**

```bash
# For each container (odoo-app, odoo-db):
#   1. docker inspect --format='{{.State.Running}}' $container
#      - Not found (exit 1) or Running=false → CRITICAL
#   2. docker inspect --format='{{.State.Health.Status}}' $container
#      - "unhealthy" → CRITICAL (even if Running=true)
#   3. docker inspect --format='{{.RestartCount}}' $container
#      - >= 5 → CRITICAL, >= 2 → WARNING
#
# Worst status wins across both containers
# Perfdata: restart counts for both containers
```

**Key docker inspect fields:**
- `{{.State.Running}}` -- "true" or "false"
- `{{.State.Health.Status}}` -- "healthy", "unhealthy", "starting", or template error if no healthcheck
- `{{.RestartCount}}` -- integer
- `{{.State.Status}}` -- "running", "exited", "restarting", etc.

**Gotcha:** Containers without healthcheck config will cause a template parsing error on `.State.Health.Status`. Both containers in this project have healthchecks defined in docker-compose.yml, but the plugin should handle the error gracefully (treat as UNKNOWN for that field, not crash).

Source: [Docker inspect docs](https://docs.docker.com/reference/cli/docker/inspect/), [Docker health status issue](https://github.com/moby/moby/issues/40323)

### Pattern 3: PostgreSQL Check via docker exec
**What:** Single plugin that collects all PG metrics in one invocation
**Logic flow:**

```bash
# Authentication: docker exec uses the container's POSTGRES_USER env var
# All queries via: docker exec -i odoo-db psql -U "$PG_USER" -d "$PG_DB" -t -A -c "QUERY"
#   -t = tuples only (no headers)
#   -A = unaligned output (no padding)
#
# Metric 1: Active connections
#   SELECT count(*) FROM pg_stat_activity;
#   (compare against max_connections=50, warn at 35, crit at 45)
#
# Metric 2: Database size (bytes)
#   SELECT pg_database_size(current_database());
#   (warn at 5GB = 5368709120, crit at 10GB = 10737418240)
#
# Metric 3: Query latency (SELECT 1 round-trip via docker exec)
#   Measure wall-clock time of: docker exec -i odoo-db psql ... -c "SELECT 1;"
#   Using bash: start=$(date +%s%N); ...; end=$(date +%s%N); latency_ms=$(( (end-start)/1000000 ))
#   (warn at 100ms, crit at 500ms -- includes docker exec overhead)
#
# Metric 4: Cache hit ratio
#   SELECT ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read) + 1), 2)
#   FROM pg_stat_database WHERE datname = current_database();
#   (warn below 90%, crit below 80%)
#
# Worst status wins across all metrics
```

**PostgreSQL queries verified against PG 18 docs:**
- `pg_stat_activity` -- one row per server process, `count(*)` gives total connections
- `pg_database_size(current_database())` -- returns bytes as bigint
- `pg_stat_database.blks_hit` and `pg_stat_database.blks_read` -- cumulative buffer cache stats
- `+1` in denominator prevents division by zero on fresh databases

Source: [PostgreSQL 18 Monitoring Stats](https://www.postgresql.org/docs/current/monitoring-stats.html)

### Pattern 4: Icinga2 Service Definition Templates (command_endpoint)
**What:** Icinga2 DSL configuration files for the master admin to import
**Architecture:** Top-down command endpoint mode -- master schedules checks, agent executes locally

```
# commands.conf -- goes in /etc/icinga2/zones.d/global-templates/
# (synced to all nodes automatically)

object CheckCommand "docker-stack" {
  command = [ "/usr/lib/nagios/plugins/custom/check_docker_stack" ]
  arguments = {
    "--container" = {
      value = "$docker_containers$"
      description = "Comma-separated container names"
    }
    "--warn-restarts" = "$docker_warn_restarts$"
    "--crit-restarts" = "$docker_crit_restarts$"
  }
  vars.docker_containers = "odoo-app,odoo-db"
  vars.docker_warn_restarts = 2
  vars.docker_crit_restarts = 5
}

# services.conf -- goes in /etc/icinga2/zones.d/master/
# (master-local configuration)

apply Service "docker-stack" {
  check_command = "docker-stack"
  command_endpoint = host.vars.agent_endpoint
  check_interval = 5m
  retry_interval = 1m
  max_check_attempts = 3
  groups = [ "odoo-production" ]
  assign where host.vars.odoo_host == true
}
```

**Key insight:** `command_endpoint = host.vars.agent_endpoint` tells the master to execute the check on the agent, not locally. The agent needs the plugin binary at the path specified in the CheckCommand.

Source: [Icinga2 Distributed Monitoring](https://icinga.com/docs/icinga-2/latest/doc/06-distributed-monitoring/), [Icinga2 Object Types](https://icinga.com/docs/icinga-2/latest/doc/09-object-types/)

### Pattern 5: Notification Email Templates
**What:** Icinga2 ships with `mail-service-notification.sh` in `/etc/icinga2/scripts/`
**Approach:** Provide example notification apply rules that use the built-in Icinga2 mail notification commands, not custom scripts. The master admin already has mail infrastructure -- we provide the notification routing rules for the odoo-production service group.

```
# Built-in Icinga2 notification commands:
# - mail-service-notification (already exists on any Icinga2 install)
# - mail-host-notification (already exists on any Icinga2 install)
#
# We only provide: apply Notification rules scoped to odoo-production services
```

Source: [Icinga2 mail-service-notification.sh](https://github.com/Icinga/icinga2/blob/master/etc/icinga2/scripts/mail-service-notification.sh)

### Anti-Patterns to Avoid
- **Per-container plugins:** Don't create separate check plugins for each container. Single plugin checks both, worst status wins. Reduces scheduling overhead and keeps alerts correlated.
- **Host-level psql client:** Don't install PostgreSQL client on the host. `docker exec` keeps the architecture Docker-only and avoids version mismatch issues.
- **Ready-to-drop .conf files:** Don't provide files that claim to work without editing. Every Icinga2 deployment has different host names, zones, and notification groups. Parameterized templates with clear placeholders are honest and safer.
- **Polling docker ps:** Don't parse `docker ps` output. Use `docker inspect --format` with Go templates for reliable, structured output.
- **Hardcoded credentials in plugins:** PostgreSQL credentials should be read from the environment or the .env file, never hardcoded in the plugin script.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Nagios perfdata formatting | Custom format strings | Standard `label=value;warn;crit;min;max` convention | Icinga2/Grafana/PNP4Nagios all parse this format automatically |
| Email notifications | Custom mail scripts | Icinga2's built-in `mail-service-notification` command | Already handles OS detection, mail command differences, HTML formatting |
| Container enumeration | Custom container discovery | Hardcoded container names (odoo-app, odoo-db) | Only 2 containers, dynamic discovery adds complexity for zero benefit |
| PostgreSQL client | Host-installed psql | `docker exec -i odoo-db psql` | Already available, no install, no network routing, no credential duplication |
| Threshold parsing | Custom argument parsing | `getopts` with standard `--warn`/`--crit` flags | Consistent with Nagios plugin conventions, familiar to any admin |

**Key insight:** The monitoring domain has 30+ years of conventions (Nagios Plugin API). Following them exactly means Icinga2 parses output automatically, thresholds display correctly in the web UI, and perfdata graphs work without configuration.

## Common Pitfalls

### Pitfall 1: Docker Health Status Template Error
**What goes wrong:** `docker inspect --format='{{.State.Health.Status}}'` throws a template parsing error on containers without healthcheck definitions.
**Why it happens:** The `.State.Health` object is nil when no healthcheck is configured in the image or compose file.
**How to avoid:** Both containers in this project have healthchecks (verified in docker-compose.yml), but the plugin should use `docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}'` as a defensive pattern.
**Warning signs:** Plugin exits with code 3 (UNKNOWN) when it should exit 0 (OK).

### Pitfall 2: docker exec Timing Includes Overhead
**What goes wrong:** Query latency measurement via `docker exec` includes container exec overhead (~20-50ms), not just SQL execution time.
**Why it happens:** `docker exec` creates a new process inside the container, which has non-trivial startup cost.
**How to avoid:** Set latency thresholds higher than you would for a direct psql connection. Recommended: warn at 100ms, crit at 500ms. These thresholds account for docker exec overhead while still detecting genuine database performance degradation.
**Warning signs:** Latency always reads 30-60ms even on idle systems.

### Pitfall 3: Cache Hit Ratio Division by Zero
**What goes wrong:** `blks_hit / (blks_hit + blks_read)` returns NULL or errors on a fresh database with zero reads.
**Why it happens:** Both blks_hit and blks_read are 0 after a fresh PostgreSQL start or database creation.
**How to avoid:** Add `+1` to denominator: `sum(blks_hit) / (sum(blks_hit) + sum(blks_read) + 1)`. Alternatively, treat the case of `blks_hit + blks_read = 0` as OK (no data to cache yet).
**Warning signs:** Plugin returns UNKNOWN immediately after system restart.

### Pitfall 4: Icinga2 User Needs Docker Access
**What goes wrong:** Check plugins fail with "permission denied" when executed by the Icinga2 agent.
**Why it happens:** The Icinga2 agent runs as the `nagios` user (Debian/Ubuntu convention), which does not have access to the Docker socket by default.
**How to avoid:** Add the `nagios` user to the `docker` group: `usermod -aG docker nagios`. This is a common requirement documented across all Docker monitoring guides. The plugin should detect this failure and return UNKNOWN with a clear error message.
**Warning signs:** Plugin works when run manually as root but returns UNKNOWN when executed by Icinga2.

### Pitfall 5: Perfdata Labels with Spaces
**What goes wrong:** Performance data labels containing spaces break Icinga2 parsing.
**Why it happens:** The Nagios perfdata spec uses spaces as delimiters between metrics.
**How to avoid:** Use underscores or dashes in labels: `odoo_restarts=0;2;5;0;` not `odoo restarts=0;2;5;0;`.
**Warning signs:** Only the first metric shows up in Icinga2 performance data graphs.

### Pitfall 6: pg_stat_activity Connection Count Includes Self
**What goes wrong:** The check connection itself counts as an active connection, inflating the count by 1.
**Why it happens:** The psql session running the monitoring query is a connection.
**How to avoid:** This is typically negligible (1 connection out of 50 max), but document it. Do not subtract 1 -- the check connection is real load.
**Warning signs:** Connection count never reaches 0 even on an idle system.

## Code Examples

### Docker Container Health Check (verified pattern)
```bash
#!/usr/bin/env bash
# check_docker_stack — Icinga2/Nagios plugin for Docker container health
# Exit codes: 0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN

set -uo pipefail

# Defaults
CONTAINERS="odoo-app,odoo-db"
WARN_RESTARTS=2
CRIT_RESTARTS=5

# ... getopts parsing ...

overall_status=0  # 0=OK, track worst

for container in ${CONTAINERS//,/ }; do
  # Check if container exists and is running
  running=$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "CRITICAL - Container $container does not exist"
    exit 2
  fi
  if [[ "$running" != "true" ]]; then
    echo "CRITICAL - Container $container is not running (State: $(docker inspect --format='{{.State.Status}}' "$container"))"
    exit 2
  fi

  # Check health status (defensive for containers without healthcheck)
  health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container" 2>/dev/null)
  if [[ "$health" == "unhealthy" ]]; then
    echo "CRITICAL - Container $container is unhealthy"
    exit 2
  fi

  # Check restart count
  restarts=$(docker inspect --format='{{.RestartCount}}' "$container" 2>/dev/null)
  restarts=${restarts:-0}
  if (( restarts >= CRIT_RESTARTS )); then
    [[ $overall_status -lt 2 ]] && overall_status=2
  elif (( restarts >= WARN_RESTARTS )); then
    [[ $overall_status -lt 1 ]] && overall_status=1
  fi
done

# Build output with perfdata
# OK - All containers healthy | 'odoo-app_restarts'=0;2;5;0; 'odoo-db_restarts'=0;2;5;0;
```

Source: Pattern derived from [Nagios Docker check gist](https://gist.github.com/ekristen/11254304) and [check_docker](https://github.com/timdaman/check_docker)

### PostgreSQL Health Check (verified queries)
```bash
#!/usr/bin/env bash
# check_postgres_health — Icinga2/Nagios plugin for PostgreSQL metrics via docker exec

CONTAINER="odoo-db"
PG_USER="${PG_USER:-odoo}"
PG_DB="${PG_DB:-odoo}"

# Helper: run psql query inside container
pg_query() {
  docker exec -i "$CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -t -A -c "$1" 2>/dev/null
}

# Metric 1: Connection count
connections=$(pg_query "SELECT count(*) FROM pg_stat_activity;")

# Metric 2: Database size in bytes
db_size=$(pg_query "SELECT pg_database_size(current_database());")

# Metric 3: Query latency (includes docker exec overhead)
start_ns=$(date +%s%N)
pg_query "SELECT 1;" >/dev/null
end_ns=$(date +%s%N)
latency_ms=$(( (end_ns - start_ns) / 1000000 ))

# Metric 4: Cache hit ratio
cache_ratio=$(pg_query "SELECT ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read) + 1), 2) FROM pg_stat_database WHERE datname = current_database();")

# Evaluate thresholds, build status text + perfdata
# 'connections'=12;35;45;0;50 'db_size'=1073741824B;5368709120;10737418240;0;
# 'query_latency'=45ms;100;500;0; 'cache_hit_ratio'=99.5%;90;80;0;100
```

Source: [PostgreSQL 18 Cumulative Statistics](https://www.postgresql.org/docs/current/monitoring-stats.html)

### Icinga2 CheckCommand Definition (verified syntax)
```
// Source: https://icinga.com/docs/icinga-2/latest/doc/09-object-types/
object CheckCommand "docker-stack" {
  command = [ "/usr/lib/nagios/plugins/custom/check_docker_stack" ]
  arguments = {
    "--containers" = {
      value = "$docker_stack_containers$"
      description = "Comma-separated container names to check"
    }
    "--warn-restarts" = {
      value = "$docker_stack_warn_restarts$"
      description = "Restart count warning threshold"
    }
    "--crit-restarts" = {
      value = "$docker_stack_crit_restarts$"
      description = "Restart count critical threshold"
    }
  }
  vars.docker_stack_containers = "odoo-app,odoo-db"
  vars.docker_stack_warn_restarts = 2
  vars.docker_stack_crit_restarts = 5
}
```

### Icinga2 Service Apply with command_endpoint (verified syntax)
```
// Source: https://icinga.com/docs/icinga-2/latest/doc/06-distributed-monitoring/
apply Service "docker-stack" {
  check_command = "docker-stack"
  command_endpoint = host.vars.agent_endpoint
  check_interval = 5m
  retry_interval = 1m
  max_check_attempts = 3
  groups = [ "odoo-production" ]
  assign where host.vars.odoo_host == true
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NRPE (Nagios Remote Plugin Executor) | Icinga2 command_endpoint (native) | Icinga2 2.x (2014+) | No separate NRPE daemon needed; master sends execution events over Icinga2's own TLS connection |
| check_postgres (Perl, host-level) | docker exec + psql (container-native) | Docker adoption | No host-level PG client, no network routing to internal Docker network, credentials already in container env |
| Per-container Nagios plugins | Single plugin checking all containers | Best practice | Reduces check scheduling overhead, correlates container status in one alert |
| Text-only email notifications | Icinga2 built-in mail commands | Icinga2 2.x | OS-aware (detects Debian mailutils vs RHEL mailx), handles HTML formatting |

**Deprecated/outdated:**
- **NRPE:** Still works but unnecessary with Icinga2's native command_endpoint. Adds a separate daemon, separate TLS config, and separate firewall port.
- **check_postgres Perl plugin:** Still maintained but requires host-level psql client and direct network access to PostgreSQL. Overkill when running in Docker with only 4 metrics needed.

## Open Questions

1. **Nagios user group on Ubuntu 24.04 with Icinga2 agent**
   - What we know: Icinga2 agent on Debian/Ubuntu typically runs as `nagios` user. The `nagios` user needs Docker group membership to run `docker inspect` and `docker exec`.
   - What's unclear: Whether the Icinga2 master's agent install script already adds the `nagios` user to the `docker` group, or if this is a manual step.
   - Recommendation: Document `usermod -aG docker nagios` in the README as a prerequisite. The master admin can confirm if their install script handles this.

2. **Plugin deployment path on agent**
   - What we know: Icinga2 default plugin directory is `/usr/lib/nagios/plugins/`. Custom plugins often go in a subdirectory like `/usr/lib/nagios/plugins/custom/`.
   - What's unclear: Whether the Icinga2 master project expects plugins in the default path or a custom path.
   - Recommendation: Use `/usr/lib/nagios/plugins/custom/` and document a `CustomPluginDir` constant in the README. The deploy script copies from `monitoring/plugins/` to the target path.

3. **Query latency thresholds**
   - What we know: `docker exec` overhead is ~20-50ms. A healthy PostgreSQL `SELECT 1` takes <1ms.
   - What's unclear: Exact overhead on the production droplet (2 vCPU / 4GB).
   - Recommendation: Warn at 100ms, critical at 500ms. Conservative enough to avoid false positives from docker exec overhead, sensitive enough to detect genuine database issues. Tunable via plugin arguments.

## Sources

### Primary (HIGH confidence)
- [Nagios Plugin API](https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/3/en/pluginapi.html) -- exit codes, output format, perfdata specification
- [Icinga2 Service Monitoring](https://icinga.com/docs/icinga-2/latest/doc/05-service-monitoring/) -- CheckCommand definition, custom plugin directory, PluginDir constant
- [Icinga2 Object Types](https://icinga.com/docs/icinga-2/latest/doc/09-object-types/) -- CheckCommand, Service, ServiceGroup, Host, Notification DSL syntax
- [Icinga2 Distributed Monitoring](https://icinga.com/docs/icinga-2/latest/doc/06-distributed-monitoring/) -- command_endpoint, zone configuration, top-down approach
- [Icinga2 Monitoring Basics](https://icinga.com/docs/icinga-2/latest/doc/03-monitoring-basics/) -- apply rules, service groups, check intervals
- [PostgreSQL 18 Monitoring Stats](https://www.postgresql.org/docs/current/monitoring-stats.html) -- pg_stat_activity, pg_stat_database, pg_database_size
- [Docker inspect CLI reference](https://docs.docker.com/reference/cli/docker/inspect/) -- Go template format, State fields

### Secondary (MEDIUM confidence)
- [Nagios Docker check gist (ekristen)](https://gist.github.com/ekristen/11254304) -- Bash Docker check pattern, verified against Docker inspect docs
- [check_docker (timdaman)](https://github.com/timdaman/check_docker) -- Python Docker check, reference for health and restart monitoring
- [Icinga2 mail-service-notification.sh](https://github.com/Icinga/icinga2/blob/master/etc/icinga2/scripts/mail-service-notification.sh) -- Built-in notification script, parameter conventions
- [Docker Health Status issue #40323](https://github.com/moby/moby/issues/40323) -- Template parsing error on containers without healthcheck

### Tertiary (LOW confidence)
- Query latency thresholds (100ms/500ms) -- derived from estimated docker exec overhead, not measured on production hardware. Needs validation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Nagios Plugin API and Icinga2 DSL are well-documented, stable standards. bash + docker inspect + docker exec psql is a proven pattern.
- Architecture: HIGH -- command_endpoint mode is the documented best practice for Icinga2 distributed monitoring. Plugin structure follows established conventions.
- Pitfalls: HIGH -- Docker health template error, docker exec timing overhead, and nagios user permissions are well-documented issues with verified solutions.
- Threshold values: MEDIUM -- Connection and DB size thresholds are calculated from known max_connections=50 and reasonable growth expectations. Query latency thresholds are estimated.

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable domain, 30-day validity)
