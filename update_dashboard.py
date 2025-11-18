#!/usr/bin/env python3
import json
import os
import re
from pathlib import Path
import urllib.parse

# Configuration
DOZZLE_URL = "https://logs.dumitruvulpe.com"
DASHBOARD_OUTPUT_DIR = "./stacks/monitoring/dashboards"

def discover_stacks(stacks_dir="./stacks"):
    """
    Auto-discover stacks by scanning the stacks directory.
    Reads docker-compose.yml files to find container_name declarations.
    Returns a dict mapping stack_name -> {"pattern": pattern, "containers": [list of container names]}
    """
    stacks = {}
    stacks_path = Path(stacks_dir)

    if not stacks_path.exists():
        print(f"Error: Stacks directory '{stacks_dir}' not found")
        return stacks

    for stack_dir in sorted(stacks_path.iterdir()):
        if not stack_dir.is_dir():
            continue

        compose_file = stack_dir / "docker-compose.yml"
        if not compose_file.exists():
            continue

        stack_name = stack_dir.name
        container_names = []

        # Read docker-compose.yml and extract container_name values
        with open(compose_file, 'r') as f:
            for line in f:
                # Match: container_name: some_name
                match = re.search(r'container_name:\s*(.+)', line)
                if match:
                    container_name = match.group(1).strip()
                    container_names.append(container_name)

        if container_names:
            # If multiple containers, create a regex group pattern
            if len(container_names) == 1:
                pattern = container_names[0]
                # If no explicit container_name, use pattern matching
                if not pattern:
                    pattern = f"{stack_name}.*"
            else:
                # Create regex OR pattern: (name1|name2|name3)
                pattern = f"({'|'.join(container_names)})"

            stacks[stack_name] = {
                "pattern": pattern,
                "containers": container_names
            }
        else:
            # No explicit container_name found, use wildcard pattern
            # Docker Compose auto-generates names like: stackname-servicename-1
            stacks[stack_name] = {
                "pattern": f"{stack_name}.*",
                "containers": []  # Will be determined at runtime
            }

    return stacks

def create_row_panels(stack_name, pattern, y_position):
    """Create all 6 panels for a single stack row with drilldown link"""

    panels = []

    # Status panel - shows running and total container counts, title links to detail dashboard
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
            "textMode": "value_and_name",
            "colorMode": "background",
            "justifyMode": "center",
            "orientation": "vertical",
            "reduceOptions": {
                "values": False,
                "calcs": ["lastNotNull"]
            }
        },
        "targets": [
            {
                "expr": f'count(count_over_time(container_last_seen{{name=~"{pattern}"}}[1m])) or vector(0)',
                "refId": "A",
                "legendFormat": "Running"
            },
            {
                "expr": f'count(group by (name) (container_start_time_seconds{{name=~"{pattern}"}})) or vector(0)',
                "refId": "B",
                "legendFormat": "Total"
            }
        ],
        "title": f"{stack_name.title()} Status",
        "type": "stat",
        "links": [
            {
                "title": f"Stackr: {stack_name.title()}",
                "url": f"/d/stack-{stack_name}",
                "targetBlank": False
            }
        ]
    })

    # CPU panel - timeline graph
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "percent",
                "decimals": 1,
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "showPoints": "never",
                    "fillOpacity": 10,
                    "lineWidth": 1,
                    "spanNulls": False,
                    "stacking": {"mode": "none", "group": "A"},
                    "hideFrom": {"tooltip": False, "viz": False, "legend": False}
                }
            }
        },
        "gridPos": {"h": 4, "w": 4, "x": 3, "y": y_position},
        "id": None,
        "options": {
            "legend": {
                "displayMode": "hidden",
                "placement": "bottom",
                "showLegend": False
            },
            "tooltip": {
                "mode": "single",
                "sort": "none"
            }
        },
        "targets": [
            {
                "expr": f'sum(rate(container_cpu_usage_seconds_total{{name=~"{pattern}"}}[5m]) * 100)',
                "refId": "A",
                "legendFormat": "CPU",
                "datasource": {"type": "prometheus", "uid": "prometheus"}
            }
        ],
        "title": f"{stack_name.title()} CPU",
        "type": "timeseries"
    })

    # Memory panel - timeline graph
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "bytes",
                "decimals": 1,
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "showPoints": "never",
                    "fillOpacity": 10,
                    "lineWidth": 1,
                    "spanNulls": False,
                    "stacking": {"mode": "none", "group": "A"},
                    "hideFrom": {"tooltip": False, "viz": False, "legend": False}
                }
            }
        },
        "gridPos": {"h": 4, "w": 4, "x": 7, "y": y_position},
        "id": None,
        "options": {
            "legend": {
                "displayMode": "hidden",
                "placement": "bottom",
                "showLegend": False
            },
            "tooltip": {
                "mode": "single",
                "sort": "none"
            }
        },
        "targets": [
            {
                "expr": f'sum(container_memory_usage_bytes{{name=~"{pattern}"}})',
                "refId": "A",
                "legendFormat": "Memory",
                "datasource": {"type": "prometheus", "uid": "prometheus"}
            }
        ],
        "title": f"{stack_name.title()} Memory",
        "type": "timeseries"
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
        "gridPos": {"h": 4, "w": 5, "x": 11, "y": y_position},
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
        "gridPos": {"h": 4, "w": 5, "x": 16, "y": y_position},
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

    # Errors panel - small square, green if 0, red if errors
    panels.append({
        "datasource": {"type": "loki", "uid": "loki"},
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": 0},
                        {"color": "red", "value": 1}
                    ]
                },
                "unit": "none"
            }
        },
        "gridPos": {"h": 4, "w": 3, "x": 21, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "none",
            "textMode": "value",
            "colorMode": "background",
            "justifyMode": "center"
        },
        "targets": [
            {
                "expr": f'sum(count_over_time({{container=~"{pattern}",detected_level="error"}} [$__range])) or vector(0)',
                "refId": "A"
            }
        ],
        "title": f"{stack_name.title()} Errors",
        "type": "stat"
    })

    return panels

def create_container_row_panels(container_name, y_position):
    """Create detailed panels for a single container"""
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
        "gridPos": {"h": 4, "w": 2, "x": 0, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "none",
            "textMode": "value",
            "colorMode": "background",
            "justifyMode": "center"
        },
        "targets": [
            {
                "expr": f'count(container_start_time_seconds{{name="{container_name}"}}) or vector(0)',
                "refId": "A"
            }
        ],
        "title": f"{container_name} Status",
        "type": "stat"
    })

    # CPU graph
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "percent",
                "decimals": 1,
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "showPoints": "never",
                    "fillOpacity": 10,
                    "lineWidth": 1,
                    "spanNulls": False,
                    "stacking": {"mode": "none", "group": "A"},
                    "hideFrom": {"tooltip": False, "viz": False, "legend": False}
                }
            }
        },
        "gridPos": {"h": 4, "w": 5, "x": 2, "y": y_position},
        "id": None,
        "options": {
            "legend": {"displayMode": "hidden", "placement": "bottom", "showLegend": False},
            "tooltip": {"mode": "single", "sort": "none"}
        },
        "targets": [
            {
                "expr": f'rate(container_cpu_usage_seconds_total{{name="{container_name}"}}[5m]) * 100',
                "refId": "A",
                "legendFormat": "CPU",
                "datasource": {"type": "prometheus", "uid": "prometheus"}
            }
        ],
        "title": "CPU",
        "type": "timeseries"
    })

    # Memory graph
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "bytes",
                "decimals": 1,
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "showPoints": "never",
                    "fillOpacity": 10,
                    "lineWidth": 1,
                    "spanNulls": False,
                    "stacking": {"mode": "none", "group": "A"},
                    "hideFrom": {"tooltip": False, "viz": False, "legend": False}
                }
            }
        },
        "gridPos": {"h": 4, "w": 5, "x": 7, "y": y_position},
        "id": None,
        "options": {
            "legend": {"displayMode": "hidden", "placement": "bottom", "showLegend": False},
            "tooltip": {"mode": "single", "sort": "none"}
        },
        "targets": [
            {
                "expr": f'container_memory_usage_bytes{{name="{container_name}"}}',
                "refId": "A",
                "legendFormat": "Memory",
                "datasource": {"type": "prometheus", "uid": "prometheus"}
            }
        ],
        "title": "Memory",
        "type": "timeseries"
    })

    # Network I/O
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
        "gridPos": {"h": 4, "w": 5, "x": 12, "y": y_position},
        "id": None,
        "options": {
            "legend": {"displayMode": "list", "placement": "bottom"},
            "tooltip": {"mode": "multi"}
        },
        "targets": [
            {
                "expr": f'rate(container_network_receive_bytes_total{{name="{container_name}"}}[5m])',
                "refId": "A",
                "legendFormat": "RX"
            },
            {
                "expr": f'rate(container_network_transmit_bytes_total{{name="{container_name}"}}[5m])',
                "refId": "B",
                "legendFormat": "TX"
            }
        ],
        "title": "Network I/O",
        "type": "timeseries"
    })

    # Uptime
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None}
                    ]
                },
                "unit": "s"
            }
        },
        "gridPos": {"h": 4, "w": 3, "x": 17, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "none",
            "textMode": "value",
            "colorMode": "value",
            "justifyMode": "center"
        },
        "targets": [
            {
                "expr": f'time() - container_start_time_seconds{{name="{container_name}"}}',
                "refId": "A"
            }
        ],
        "title": "Uptime",
        "type": "stat"
    })

    # Restart count
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": 0},
                        {"color": "yellow", "value": 1},
                        {"color": "red", "value": 5}
                    ]
                },
                "unit": "none"
            }
        },
        "gridPos": {"h": 4, "w": 2, "x": 20, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "none",
            "textMode": "value",
            "colorMode": "background",
            "justifyMode": "center"
        },
        "targets": [
            {
                "expr": f'changes(container_start_time_seconds{{name="{container_name}"}}[24h])',
                "refId": "A"
            }
        ],
        "title": "Restarts (24h)",
        "type": "stat"
    })

    # Errors
    panels.append({
        "datasource": {"type": "loki", "uid": "loki"},
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": 0},
                        {"color": "red", "value": 1}
                    ]
                },
                "unit": "none"
            }
        },
        "gridPos": {"h": 4, "w": 2, "x": 22, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "none",
            "textMode": "value",
            "colorMode": "background",
            "justifyMode": "center"
        },
        "targets": [
            {
                "expr": f'sum(count_over_time({{container="{container_name}",detected_level="error"}} [$__range])) or vector(0)',
                "refId": "A"
            }
        ],
        "title": "Errors",
        "type": "stat"
    })

    return panels

def generate_detail_dashboard(stack_name, stack_data):
    """Generate a detailed dashboard for a single stack"""
    pattern = stack_data['pattern']
    containers = stack_data['containers']

    # If no containers specified, we'll just show aggregate data
    if not containers:
        containers = [stack_name]  # Use stack name as fallback

    dashboard = {
        "title": f"Stackr: {stack_name.title()}",
        "panels": [],
        "schemaVersion": 36,
        "version": 1,
        "refresh": "30s",
        "editable": True,
        "links": [
            {
                "title": "Back to Stackr Overview",
                "url": "/d/stack-overview",
                "type": "link",
                "icon": "dashboard"
            },
            {
                "title": "View Logs in Dozzle",
                "url": f"{DOZZLE_URL}",
                "type": "link",
                "icon": "external link",
                "targetBlank": True
            }
        ]
    }

    all_panels = []
    panel_id = 1
    y_position = 0

    # Create panels for each container
    for container_name in containers:
        container_panels = create_container_row_panels(container_name, y_position)

        for panel in container_panels:
            panel['id'] = panel_id
            panel_id += 1

        all_panels.extend(container_panels)
        y_position += 4

    dashboard['panels'] = all_panels

    return dashboard

def generate_dashboard():
    """Generate dashboard by auto-discovering stacks and creating panels for each"""

    dashboard_path = "./stacks/monitoring/dashboards/stack-overview.json"

    # Auto-discover stacks
    print("Discovering stacks...")
    stacks = discover_stacks()

    if not stacks:
        print("No stacks found!")
        return

    print(f"Found {len(stacks)} stacks:")
    for stack_name, stack_data in stacks.items():
        print(f"  - {stack_name}: {stack_data['pattern']}")

    # Read existing dashboard to preserve metadata
    if os.path.exists(dashboard_path):
        with open(dashboard_path, 'r') as f:
            dashboard = json.load(f)
    else:
        # Create minimal dashboard structure if it doesn't exist
        dashboard = {
            "title": "Stackr Overview",
            "panels": [],
            "schemaVersion": 36,
            "version": 1,
            "refresh": "30s"
        }

    # Generate all panels
    all_panels = []
    panel_id = 1
    y_position = 0

    # Create panels for each stack (reusing the same panel structure)
    for stack_name, stack_data in stacks.items():
        row_panels = create_row_panels(stack_name, stack_data['pattern'], y_position)

        # Assign IDs to each panel
        for panel in row_panels:
            panel['id'] = panel_id
            panel_id += 1

        all_panels.extend(row_panels)
        y_position += 4

    # Update dashboard
    dashboard['panels'] = all_panels
    dashboard['title'] = 'Stackr Overview'

    # Write updated dashboard
    with open(dashboard_path, 'w') as f:
        json.dump(dashboard, f, indent=2)

    print(f"\n✓ Generated overview dashboard with {len(all_panels)} panels ({len(stacks)} stacks × 6 panels each)")
    print(f"✓ Written to {dashboard_path}")

    # Generate detail dashboards for each stack
    print(f"\nGenerating detail dashboards...")

    # Create stacks subdirectory if it doesn't exist
    stacks_subdir = f"{DASHBOARD_OUTPUT_DIR}/stacks"
    os.makedirs(stacks_subdir, exist_ok=True)

    for stack_name, stack_data in stacks.items():
        detail_dashboard = generate_detail_dashboard(stack_name, stack_data)
        detail_path = f"{stacks_subdir}/stack-{stack_name}.json"

        with open(detail_path, 'w') as f:
            json.dump(detail_dashboard, f, indent=2)

        container_count = len(stack_data['containers']) if stack_data['containers'] else 1
        print(f"  ✓ {stack_name}: {container_count} containers → {detail_path}")

    print(f"\n✓ Generated {len(stacks)} detail dashboards")

if __name__ == '__main__':
    generate_dashboard()
