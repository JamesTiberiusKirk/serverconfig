# Stackr stack

This stack runs Stackr (the deployment + cron API) inside Docker using the
published image from ghcr.io/jamestiberiuskirk/stackr. The container keeps the
repository mounted at `/srv/stackr_repo`, watches `/srv/stackr_repo/.env`, and
shares the Docker socket to execute `stackr` commands on behalf of callers.

For more information about Stackr itself, see https://github.com/jamestiberiuskirk/stackr

## Usage

Populate the Stackr variables in `.env`, then run:

```bash
./stackr stackr update
```

Traefik routes requests to `https://${STACKR_DOMAIN}` and checks `/healthz` for
liveness. Stackr automatically reloads cron schedules whenever any Compose file
inside `stacks/` changes, so editing `docker-compose.yml` is enough to add or
update jobs. Repository-wide defaults (stack paths, cron conventions, etc.) live
in `.stackr.yaml`.
