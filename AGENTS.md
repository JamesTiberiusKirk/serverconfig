# Repository Guidelines

## Project Structure & Module Organization
- Stacks: `stacks/<service>/docker-compose.yml` per service (e.g., `stacks/immich`, `stacks/jellyfin`).
- Reverse proxy: `stacks/traefik/` (Traefik v2) with Docker provider and dynamic files in `stacks/traefik/dynamic/`.
- Orchestration: `run.sh` computes env vars and orchestrates `docker compose` across stacks.
- Config: `.env` (local, ignored) and `example.env` (template). Ensure `.env` defines `COMPOSE_DIRECTORY`, `STACK_HDD_STORAGE`, and `STACK_SSD_STORAGE` to match `run.sh`.
- Storage: `.vols_hdd/` and `.vols_ssd/` at the repo root; some stacks also have local `.vols_*` directories.
- Archives: legacy NPM proxy moved to `misc/archive/proxy/`.

## Build, Test, and Development Commands
- `./run.sh --dry-run all`: print resolved compose config and paths without changes.
- `./run.sh <stack>`: start/update a specific stack (e.g., `traefik`, `immich`).
- `./run.sh <stack> tear-down`: bring a specific stack down.
- `./run.sh <stack> get-vars`: append any missing env vars for that stack to `.env`.
- `./run.sh <stack> vars-only -- <cmd>`: export computed vars, then execute `<cmd>`.
- `make check_script`: run ShellCheck on `run.sh` (POSIX `sh`).

## Coding Style & Naming Conventions
- Shell: POSIX `sh`; prefer simple, portable constructs. Use `make check_script` locally.
- YAML: 2‑space indentation; lowercase service and directory names.
- Env vars: UPPER_SNAKE_CASE. Required by `run.sh`: `COMPOSE_DIRECTORY`, `STACK_HDD_STORAGE`, `STACK_SSD_STORAGE`.
- Example `.env`:
  ```
  COMPOSE_DIRECTORY=./stacks/
  STACK_HDD_STORAGE=/mnt/hdd
  STACK_SSD_STORAGE=/mnt/ssd
  ```

## Testing Guidelines
- Dry‑run first: `./run.sh --dry-run <stack|all>` to verify env resolution and compose config.
- Direct compose check: `docker compose --file stacks/<service>/docker-compose.yml config`.
- Verify `.env` completeness: `./run.sh <stack> get-vars`, then review inserted section in `.env`.
- Each stack must contain `docker-compose.yml` at `stacks/<service>/`.
- Traefik network is auto-created; stacks declare `networks.traefik.name: traefik`.

## Security & Configuration Tips
- Do not commit secrets; `.env` is ignored by `.gitignore`. Start from `example.env` and align keys with `run.sh`.
- Use absolute storage paths in `.env` for `STACK_HDD_STORAGE` and `STACK_SSD_STORAGE`.
- The script creates missing storage directories when safe; review paths on first run.
