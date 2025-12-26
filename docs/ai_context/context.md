# AI Context

## Repository overview
- Docker Compose stacks live under `stacks/<name>/` (Traefik, Jellyfin, mx5parts, Stackr, etc.).
- `.stackr.yaml` (tracked) is the source of truth for:
  - `stacks_dir`, cron defaults, HTTP base domain.
  - Paths: `backup_dir`, `pools` (creates `$STACKR_PROV_POOL_*`), and `custom` (custom env vars per path).
  - Deploy metadata per stack (`tag_env`, `args`).
  - Non-secret env overrides (`env.global`, `env.stacks.<name>`).
- `.env` is git-ignored and only needed for secrets (e.g., DB creds, domains). The Go CLI auto-populates compose/storage/env values from `.stackr.yaml`.
- `stackr` CLI (`stackr/cmd/stackr`) mirrors `run.sh` commands: `all`, `update`, `backup`, `vars-only`, `get-vars`, `tear-down`, `--dry-run`, etc.
- Stackr API (`stackr/cmd/stackrd`):
  - Serves `/deploy` (rewrites tag env + runs CLI) and `/healthz`.
  - Discovers cron jobs via `stackr.cron.*` labels and schedules them.
  - Watches `stacks/` and `.stackr.yaml` for live reloads.

## Key behaviors
- CLI creates repo-relative defaults when `.env` omits compose/storage paths.
- Backup/pools/custom dirs from `.stackr.yaml` are ensured once; per-stack pools are only materialized if the env var is used (`STACKR_PROV_POOL_*`).
- Deploy API validates stack directories exist and pulls tag/env metadata from `.stackr.yaml` instead of hard-coded catalog entries.
- Tests (`go test ./stackr/...`) and lint (`golangci-lint run ./...`) should be run with `GOCACHE=$(mktemp -d)` to avoid cache permission issues in the sandbox.

## Recent changes
- Removed hard-coded `StackCatalog`; deployments derive metadata from `.stackr.yaml`.
- Added stack-specific env injection: pools, media paths, per-stack env overrides.
- Restored missing `mx5parts` and `stackr` stacks (compose + README).
- Documentation (README, `docs/stackr.md`, `AGENTS.md`) updated to describe `.stackr.yaml` structure and CLI usage.

