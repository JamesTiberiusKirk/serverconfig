#!/usr/bin/env python3
import json
import os
import re
from pathlib import Path

def discover_stacks(stacks_dir="./stacks"):
    """
    Auto-discover stacks by scanning the stacks directory.
    Reads docker-compose.yml files to find container_name declarations.
    Returns a dict mapping stack_name -> container_name_pattern
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

            stacks[stack_name] = pattern
        else:
            # No explicit container_name found, use wildcard pattern
            # Docker Compose auto-generates names like: stackname-servicename-1
            stacks[stack_name] = f"{stack_name}.*"

    return stacks

def create_row_panels(stack_name, pattern, y_position):
    """Create all 6 panels for a single stack row"""

    panels = []

    # Status panel - shows running and total container counts
    panels.append({
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "mappings": [],
                "thresholds": {
                    "mode": "percentage",
                    "steps": [
                        {"color": "red", "value": None},
                        {"color": "yellow", "value": 50},
                        {"color": "green", "value": 100}
                    ]
                },
                "unit": "none"
            }
        },
        "gridPos": {"h": 4, "w": 3, "x": 0, "y": y_position},
        "id": None,
        "options": {
            "graphMode": "none",
            "textMode": "name",
            "colorMode": "background",
            "justifyMode": "center",
            "reduceOptions": {
                "values": False,
                "calcs": ["lastNotNull"]
            }
        },
        "targets": [
            {
                "expr": f'count(container_last_seen{{name=~"{pattern}"}} > bool (time() - 60)) or vector(0)',
                "refId": "Running",
                "legendFormat": "Running"
            },
            {
                "expr": f'count(container_start_time_seconds{{name=~"{pattern}"}}) or vector(0)',
                "refId": "Total",
                "legendFormat": "Total"
            }
        ],
        "title": f"{stack_name.title()} Status",
        "type": "stat"
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
                    "fillOpacity": 10
                }
            }
        },
        "gridPos": {"h": 4, "w": 3, "x": 3, "y": y_position},
        "id": None,
        "options": {
            "legend": {"displayMode": "hidden"},
            "tooltip": {"mode": "single"}
        },
        "targets": [
            {
                "expr": f'sum(rate(container_cpu_usage_seconds_total{{name=~"{pattern}"}}[5m]) * 100)',
                "refId": "A",
                "legendFormat": "CPU"
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
                    "fillOpacity": 10
                }
            }
        },
        "gridPos": {"h": 4, "w": 3, "x": 6, "y": y_position},
        "id": None,
        "options": {
            "legend": {"displayMode": "hidden"},
            "tooltip": {"mode": "single"}
        },
        "targets": [
            {
                "expr": f'sum(container_memory_usage_bytes{{name=~"{pattern}"}})',
                "refId": "A",
                "legendFormat": "Memory"
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
    """Generate dashboard by auto-discovering stacks and creating panels for each"""

    dashboard_path = "./stacks/monitoring/dashboards/stack-overview.json"

    # Auto-discover stacks
    print("Discovering stacks...")
    stacks = discover_stacks()

    if not stacks:
        print("No stacks found!")
        return

    print(f"Found {len(stacks)} stacks:")
    for stack_name, pattern in stacks.items():
        print(f"  - {stack_name}: {pattern}")

    # Read existing dashboard to preserve metadata
    if os.path.exists(dashboard_path):
        with open(dashboard_path, 'r') as f:
            dashboard = json.load(f)
    else:
        # Create minimal dashboard structure if it doesn't exist
        dashboard = {
            "title": "Stack Overview",
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
    for stack_name, pattern in stacks.items():
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
    with open(dashboard_path, 'w') as f:
        json.dump(dashboard, f, indent=2)

    print(f"\n✓ Generated dashboard with {len(all_panels)} panels ({len(stacks)} stacks × 6 panels each)")
    print(f"✓ Written to {dashboard_path}")

if __name__ == '__main__':
    generate_dashboard()
