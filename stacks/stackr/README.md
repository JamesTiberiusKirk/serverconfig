# Stackr stack

This stack builds and runs Stackr (the deployment + cron API) inside Docker so
it can be managed like every other homelab service. The container keeps the
repository mounted at `/srv/serverconfig`, watches `/srv/serverconfig/.env`, and
shares the Docker socket to execute `stackr` commands on behalf of callers.

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
