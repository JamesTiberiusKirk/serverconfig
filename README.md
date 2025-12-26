# Serverconfig

Homelab stacks and automation orchestrated through Docker Compose. This repo
contains:

- Compose stacks under `stacks/<name>/`
- A Go CLI (`stackr/cmd/stackr`) that replaces `run.sh`
- The Stackr API service (`stackr/cmd/stackrd`) used by CI/CD and cron jobs
- Global configuration (`.stackr.yaml`) plus local overrides in `.env`

See `docs/stackr.md` for the full architecture overview.

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

## 2. Stackr CLI (`stackr/cmd/stackr`)

Run from the repo root:

```bash
go run ./stackr/cmd/stackr --help
go run ./stackr/cmd/stackr all update         # update every stack
go run ./stackr/cmd/stackr monitoring get-vars
go run ./stackr/cmd/stackr mx5parts vars-only -- env | grep STACK_STORAGE
```

Features:

- Commands: `all`, `tear-down`, `update`, `backup`, `vars-only`, `get-vars`
- Flags: `--dry-run` (show compose config), `-D/--debug` (verbose logging)
- `vars-only -- <cmd>` exports the computed env vars and runs `<cmd>` without
  invoking Docker Compose
- Automatically loads `.env`, `.stackr.yaml`, and per-stack compose files to
  recreate `STACK_STORAGE_*`, `DCF`, etc.

**Note:** `run.sh` is deprecated. All internal operations (API deployments, cron jobs) now use the Go CLI directly. Use `stackr` for all stack management.

---

## 3. Stackr API service (`stackr/cmd/stackrd`)

Stackr exposes a tiny HTTP API (`/deploy`, `/healthz`) and executes cron-style
jobs defined via `stackr.cron.*` labels. Run it directly:

```bash
STACKR_TOKEN=changeme go run ./stackr/cmd/stackrd
```

Or through the dedicated stack (`./run.sh stackr update`) which mounts the repo
at `/srv/serverconfig` and shares `/var/run/docker.sock`. The service:

- Watches all files under `stacks/` and `.stackr.yaml` via fsnotify
- Reloads cron jobs automatically on change
- Schedules services annotated with `stackr.cron.schedule` (and optional
  profiles/run-on-deploy)
- Handles deploy webhooks by invoking the CLI equivalent of `update`

See `docs/stackr.md` for token/env requirements.

---

## 4. Linting & tests

```bash
make lint                # golangci-lint (errcheck, govet, staticcheck, etc.)
GOCACHE=$(mktemp -d) go test ./stackr/...
```

CI should run both commands to keep the codebase healthy.

---

## 5. Useful references

- `docs/stackr.md` – runtime details, cron labels, API examples
- `docs/adrs/0001-stackr-cli-migration.md` – ADR tracking the run.sh → Go CLI journey
- `stacks/<name>/README.md` – stack-specific instructions (e.g., `stacks/mx5parts/`)

For questions or future changes (secret handling, StackCatalog migration, etc.),
discuss in issues/ADRs before editing `run.sh` or legacy scripts. The goal is to
centralize behavior in Go so both automation and operators share one path.
