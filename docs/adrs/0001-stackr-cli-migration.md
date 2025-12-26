# ADR 0001: Stackr Becomes the Source of Truth for Stack Orchestration

## Status
Accepted (Implemented)

## Context
- `run.sh` drives compose stacks today, but keeping shell + Go in sync causes drift.
- Stackr (API + CLI) should consume repository data (`.stackr.yaml`, stack dirs) and expose one implementation for deploys and cron.

## Decision
1. Consolidate orchestration logic inside Go packages under `stackr/` (env resolution, stack discovery, compose command execution).
2. Replace the hard-coded `StackCatalog` with metadata discovered from the repo (`stacks/<name>/`, manifest files, compose labels).
3. Provide a Go CLI (`stackr/cmd/stackr`) that mirrors `run.sh` commands/flags so operators can drop the shell script.
4. Keep `run.sh` only as a thin wrapper until the CLI is default.
5. The Stackr API (`stackr/cmd/stackrd`) reuses the same packages (no shelling out) for cron + HTTP requests.
6. Interact with Docker through the Compose CLI, assuming the host socket is mounted when containerized.

## Consequences
**Pros**
- One codepath for CLI, API, cron: less drift, easier testing, richer tooling.
- Repository manifests become the canonical description of stacks.
- Go code simplifies env-file safety, retries, logging, etc.

**Cons**
- Porting everything takes effort; shell users must adjust workflows.
- During migration both shell and Go paths exist.
- Still rely on `docker compose` and Docker socket access.

## Implementation Sketch
1. Build orchestration packages (env management, stack discovery, compose runner).
2. Port `run.sh` features (`--dry-run`, `vars-only`, `get-vars`, `update`, `tear-down`, `backup`) and flags to the Go CLI.
3. Switch Stackr API + cron scheduler to call those packages; remove shell calls.
4. Replace `StackCatalog` with repo metadata (`.stackr.yaml` + per-stack manifests).
5. Eventually retire `run.sh`, updating docs/README to point to the Go CLI.

## Implementation Notes (Completed)

**Date:** 2025-12-26

The migration has been completed successfully:

1. **stackcmd Package Enhanced:**
   - Added `NewManagerWithWriters()` constructor to support output capture
   - All Docker Compose commands now use configurable stdout/stderr writers
   - Maintained backward compatibility through `NewManager()` which defaults to os.Stdout/os.Stderr

2. **runner.Deploy() Migrated:**
   - Replaced shell execution of `./run.sh` with direct `stackcmd.Manager` calls
   - Added `parseDeployArgs()` helper to convert args to `stackcmd.Options`
   - Output capture preserved for API responses
   - Rollback mechanism maintained for failed deployments

3. **cronjobs.execute() Migrated:**
   - Replaced shell execution of `./run.sh` with direct `stackcmd.Manager` calls
   - Cron jobs now use vars-only mode through Go instead of shell
   - Output logging preserved for monitoring

4. **run.sh Deprecated:**
   - Added deprecation notice at top of file
   - Runtime warning printed to stderr when executed
   - Kept functional for backward compatibility

5. **Testing:**
   - All existing tests pass
   - No regressions in functionality

**Key Benefits Achieved:**
- Single Go codebase for all orchestration (CLI, API, cron)
- Better error handling and structured logging
- No more shell/Go drift
- Type-safe option configuration
- Easier testing and debugging
