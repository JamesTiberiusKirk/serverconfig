#!/usr/bin/env python3
import json

# Stack configurations - mapping stack name to container name patterns
STACKS = {
    "nextcloud": "(nextcloud|nextcloud_db|nextcloud_redis)",
    "owncloud": "(owncloud_server|owncloud_mariadb|owncloud_redis)",
    "immich": "(immich_server|immich_machine_learning|immich_redis|immich_postgres)",
    "jellyfin": "jellyfin",
    "plex": "plex",
    "traefik": "traefik",
    "monitoring": "(grafana|loki|promtail|prometheus|node-exporter|cadvisor|dozzle)",
    "portainer": "portainer.*",
    "flame": "flame",
    "vikunja": "(vikunja|vikunja_db)"
}

def create_row_panels(stack_name, pattern, y_position):
    """Create all 6 panels for a single stack row"""

    panels = []

    # Status panel
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "red", "value": None},
                        {"color": "green", "value": 1}
                    ]
                },
                "unit": "none"
            }
        },
        "gridPos": {"h": 4, "w": 3, "x": 0, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "none",
            "textMode": "value",
            "colorMode": "background",
            "justifyMode": "center"
        },
        "targets": [
            {
                "expr": f'count(container_start_time_seconds{{name=~"{pattern}"}}) or vector(0)',
                "refId": "A"
            }
        ],
        "title": f"{stack_name.title()} Status",
        "type": "stat"
    })

    # CPU panel
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None},
                        {"color": "yellow", "value": 50},
                        {"color": "red", "value": 80}
                    ]
                },
                "unit": "percent",
                "decimals": 1
            }
        },
        "gridPos": {"h": 4, "w": 3, "x": 3, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "area",
            "textMode": "value_and_name",
            "colorMode": "value",
            "justifyMode": "center"
        },
        "targets": [
            {
                "expr": f'sum(rate(container_cpu_usage_seconds_total{{name=~"{pattern}"}}[5m]) * 100)',
                "refId": "A"
            }
        ],
        "title": f"{stack_name.title()} CPU",
        "type": "stat"
    })

    # Memory panel
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None},
                        {"color": "yellow", "value": 1073741824},
                        {"color": "red", "value": 2147483648}
                    ]
                },
                "unit": "bytes",
                "decimals": 1
            }
        },
        "gridPos": {"h": 4, "w": 3, "x": 6, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "area",
            "textMode": "value_and_name",
            "colorMode": "value",
            "justifyMode": "center"
        },
        "targets": [
            {
                "expr": f'sum(container_memory_usage_bytes{{name=~"{pattern}"}})',
                "refId": "A"
            }
        ],
        "title": f"{stack_name.title()} Memory",
        "type": "stat"
    })

    # Network I/O panel
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "Bps",
                "decimals": 1,
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "showPoints": "never",
                    "fillOpacity": 10
                }
            }
        },
        "gridPos": {"h": 4, "w": 5, "x": 9, "y": y_position},
        "id": None,
        "options": {
            "legend": {"displayMode": "list", "placement": "bottom"},
            "tooltip": {"mode": "multi"}
        },
        "targets": [
            {
                "expr": f'sum(rate(container_network_receive_bytes_total{{name=~"{pattern}"}}[5m]))',
                "refId": "A",
                "legendFormat": "RX"
            },
            {
                "expr": f'sum(rate(container_network_transmit_bytes_total{{name=~"{pattern}"}}[5m]))',
                "refId": "B",
                "legendFormat": "TX"
            }
        ],
        "title": f"{stack_name.title()} Network I/O",
        "type": "timeseries"
    })

    # Disk I/O panel
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "Bps",
                "decimals": 1,
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "showPoints": "never",
                    "fillOpacity": 10
                }
            }
        },
        "gridPos": {"h": 4, "w": 5, "x": 14, "y": y_position},
        "id": None,
        "options": {
            "legend": {"displayMode": "list", "placement": "bottom"},
            "tooltip": {"mode": "multi"}
        },
        "targets": [
            {
                "expr": f'sum(rate(container_fs_reads_bytes_total{{name=~"{pattern}"}}[5m]))',
                "refId": "A",
                "legendFormat": "Read"
            },
            {
                "expr": f'sum(rate(container_fs_writes_bytes_total{{name=~"{pattern}"}}[5m]))',
                "refId": "B",
                "legendFormat": "Write"
            }
        ],
        "title": f"{stack_name.title()} Disk I/O",
        "type": "timeseries"
    })

    # Errors panel
    panels.append({
        "datasource": {"type": "loki", "uid": "loki"},
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None},
                        {"color": "yellow", "value": 1},
                        {"color": "red", "value": 10}
                    ]
                },
                "unit": "none"
            }
        },
        "gridPos": {"h": 4, "w": 5, "x": 19, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "area",
            "textMode": "value_and_name",
            "colorMode": "value",
            "justifyMode": "center"
        },
        "targets": [
            {
                "expr": f'sum(count_over_time({{container=~"{pattern}",detected_level="error"}} [$__range]))',
                "refId": "A"
            }
        ],
        "title": f"{stack_name.title()} Errors",
        "type": "stat"
    })

    return panels

def generate_dashboard():
    """Generate dashboard by creating one row definition and repeating it for each stack"""

    # Read existing dashboard to preserve metadata
    with open('stack-overview.json', 'r') as f:
        dashboard = json.load(f)

    # Generate all panels
    all_panels = []
    panel_id = 1
    y_position = 0

    # Create panels for each stack (reusing the same panel structure)
    for stack_name, pattern in STACKS.items():
        row_panels = create_row_panels(stack_name, pattern, y_position)

        # Assign IDs to each panel
        for panel in row_panels:
            panel['id'] = panel_id
            panel_id += 1

        all_panels.extend(row_panels)
        y_position += 4

    # Update dashboard
    dashboard['panels'] = all_panels
    dashboard['title'] = 'Stack Overview'

    # Write updated dashboard
    with open('stack-overview.json', 'w') as f:
        json.dump(dashboard, f, indent=2)

    print(f"Generated dashboard with {len(all_panels)} panels ({len(STACKS)} stacks × 6 panels each)")

if __name__ == '__main__':
    generate_dashboard()
