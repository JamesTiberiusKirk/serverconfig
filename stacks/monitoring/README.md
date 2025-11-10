# Monitoring Stack

Comprehensive monitoring solution with Grafana, Loki (logs), and Prometheus (metrics).

## What's Included

- **Grafana** - Visualization and dashboards
- **Loki** - Log aggregation (30-day retention)
- **Promtail** - Automatic Docker log collection
- **Prometheus** - Metrics collection (30-day retention)
- **Node Exporter** - Server metrics (CPU, RAM, Disk, Network)
- **cAdvisor** - Container metrics

## Setup

1. Fill in `.env` variables:
   ```bash
   GRAFANA_ADMIN_USER=admin
   GRAFANA_ADMIN_PASSWORD=<strong-password>
   GRAFANA_DOMAIN=grafana.dumitruvulpe.com
   ```

2. Create DNS A record for grafana.dumitruvulpe.com

3. Start the stack:
   ```bash
   ./run.sh monitoring
   ```

## Access

- **Grafana UI**: https://grafana.dumitruvulpe.com
- Login with admin credentials from `.env`

## Pre-loaded Dashboards

Dashboards are automatically loaded from `./dashboards/` directory:

### Server Metrics
- **node-exporter-full.json** - Complete server metrics (CPU, RAM, Disk, Network, etc.)
- **docker-monitoring.json** - Docker host and container overview
- **docker-cadvisor.json** - Detailed per-container metrics

### Logs
- **docker-logs.json** - Live Docker container logs viewer with filters for:
  - Container name dropdown
  - Stack/Project dropdown
  - Search box for filtering log content
  - Auto-refresh every 10 seconds

## Viewing Logs

1. Go to **Explore** in Grafana
2. Select **Loki** datasource
3. Query examples:
   ```
   # All logs from traefik container
   {container="traefik"}

   # All logs from owncloud stack
   {compose_project="owncloud"}

   # Logs containing "error" from all containers
   {container=~".+"} |= "error"

   # Last hour of logs from nextcloud
   {container="nextcloud"} [1h]
   ```

## Adding Custom Dashboards

1. Create/export dashboard JSON in Grafana
2. Save to `./dashboards/` directory
3. Grafana auto-reloads every 30 seconds
4. Commit to git

## Metrics Available

- **Server**: CPU usage, Memory, Disk I/O, Network, Load average, Temperature
- **Containers**: Per-container CPU, Memory, Network, Disk I/O
- **Docker**: Running containers, Images, Volumes

## Retention

- Logs: 30 days
- Metrics: 30 days
