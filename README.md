# Serverconfig

Homelab stacks and automation orchestrated through Docker Compose. This repo
contains:

- Compose stacks under `stacks/<name>/`
- Global configuration (`.stackr.yaml`) plus local overrides in `.env`
- Stack orchestration via [Stackr](https://github.com/jamestiberiuskirk/stackr) (external project)

Stackr has been extracted to a standalone repository and is deployed as a containerized service.

---

## 1. Configure the environment

1. Copy `example.env` to `.env` and adjust storage paths, domains, secrets, etc.
2. Edit `.stackr.yaml` (tracked in git) for repo-wide defaults:

```yaml
stacks_dir: stacks               # where all docker-compose.yml live
cron:
  profile: cron                  # canonical cron-only compose profile
defaults:
  base_domain: example.local     # optional helper for stacks
paths:
  backup_dir: ./backups
  pools:
    SSD: .vols_ssd/stack_volumes
    HDD: .vols_hdd/stack_volumes
  custom:
    MEDIA_STORAGE: .vols_hdd/Media
deploy:
  mx5parts:
    tag_env: MX5PARTS_IMAGE_TAG
    args: ["mx5parts", "update"]
env:
  global:
    TEST_VAR: test_value
  stacks:
    owncloud:
      TRUSTED_DOMAINS: 192.168.1.100,oc.example.com
```

Stack-specific secrets can stay in `.env` (git-ignored). Non‑secret defaults
should move into `.stackr.yaml` so Stackr CLI + API share the same source. If
`COMPOSE_DIRECTORY`, `STACK_HDD_STORAGE`, or `STACK_SSD_STORAGE` are missing in
`.env`, the CLI automatically falls back to `stacks/`, `.vols_hdd/`, and
`.vols_ssd/` under the repo root. `paths.backup_dir` and the `paths.media.*`
entries feed the `BACKUP_DIR`/`MEDIA_STORAGE*` environment variables used by
stacks like Jellyfin/Plex, while `paths.pools` provisions per-stack SSD/HDD
pool paths (`STACKR_PROV_POOL_SSD/HDD`). The optional `deploy` section lets you
override how Stackr’s deploy API behaves; when omitted it defaults to
`<STACK>_IMAGE_TAG` and `stackr <stack> update`. The `env` block injects
non-secret variables globally or scoped to a specific stack.

---

## 2. Stackr CLI

The Stackr CLI is available from the [Stackr repository](https://github.com/jamestiberiuskirk/stackr). Install it or run from that repository:

```bash
# From the stackr repository
stackr --help
stackr all update         # update every stack
stackr monitoring get-vars
stackr mx5parts vars-only -- env | grep STACK_STORAGE
```

Features:

- Commands: `all`, `tear-down`, `update`, `backup`, `vars-only`, `get-vars`, `compose`
- Flags: `--dry-run` (show compose config), `-D/--debug` (verbose logging), `--tag` (override image tag)
- `vars-only -- <cmd>` exports the computed env vars and runs `<cmd>` without invoking Docker Compose
- `compose` shorthand runs `docker compose -f` with the stack's compose file
- Automatically loads `.env`, `.stackr.yaml`, and per-stack compose files

**Note:** `run.sh` is deprecated. All internal operations (API deployments, cron jobs) use the Stackr service. Use the `stackr` CLI for all stack management.

---

## 3. Stackr API service

Stackr runs as a containerized service (from `ghcr.io/jamestiberiuskirk/stackr`) that exposes an HTTP API (`/deploy`, `/healthz`) and executes cron-style jobs defined via `stackr.cron.*` labels.

Deploy the stackr service:

```bash
stackr stackr update
```

The service:

- Watches all files under `stacks/` and `.stackr.yaml` via fsnotify
- Reloads cron jobs automatically on change
- Schedules services annotated with `stackr.cron.schedule` (and optional profiles/run-on-deploy)
- Handles deploy webhooks by invoking stack updates
- Mounts the repository and shares `/var/run/docker.sock` for orchestration

See the [Stackr repository](https://github.com/jamestiberiuskirk/stackr) for API documentation and configuration details.

---

## 4. Validation

The repository contains stack configurations and YAML files. Validation of stack configurations can be done through the Stackr CLI:

```bash
stackr <stack> --dry-run    # Validate compose configuration
```

---

## 5. Useful references

- [Stackr repository](https://github.com/jamestiberiuskirk/stackr) – runtime details, cron labels, API examples
- `docs/adrs/0001-stackr-cli-migration.md` – ADR tracking the run.sh → Go CLI journey and stackr extraction
- `stacks/<name>/README.md` – stack-specific instructions (e.g., `stacks/mx5parts/`)

For questions about stack orchestration and deployment, see the Stackr repository.
For questions about stack configurations in this repository, discuss in issues/ADRs.
