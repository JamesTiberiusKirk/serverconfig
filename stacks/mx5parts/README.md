## mx5parts stack

This stack deploys the private `mx5parts_store` application that lives in
`../mx5parts_store` by using the images that are published to the GitHub
Container Registry:

- `ghcr.io/jamestiberiuskirk/mx5parts_store-web`
- `ghcr.io/jamestiberiuskirk/mx5parts_store-scraper`

### Services

| Service | Description |
| --- | --- |
| `web` | Public HTTP application served through Traefik on `https://${MX5PARTS_DOMAIN}` |
| `scraper` | Periodically crawls MX5Parts and ingests the dataset (archives HTTP traffic to `${STACK_STORAGE_HDD}/scraper-archive`) |
| `postgres` | Primary datastore that persists to `${STACK_STORAGE_SSD}/postgres` |

### Environment

Add the block from `example.env` to your `.env` and adjust:

- `MX5PARTS_IMAGE_TAG` – version that matches the GHCR release (e.g. `v1.2.3`)
- `MX5PARTS_DOMAIN` – host routed through Traefik
- `MX5PARTS_POSTGRES_*` – credentials for the Postgres cluster

You must `docker login ghcr.io` with credentials that can read the private
images before running `./stackr mx5parts update`.

### Scraper scheduling

The scraper service is annotated with the `stackr.cron.schedule` label so
Stackr can trigger it automatically. By default it runs at `01:00` and `13:00`
(`0 1,13 * * *`). Update the label in `docker-compose.yml` to change the cadence.

Because the service declares the `scraper` profile, Stackr automatically enables
that profile for cron runs. The scheduled command is equivalent to:

```bash
./stackr mx5parts vars-only -- \
  docker compose --file stacks/mx5parts/docker-compose.yml \
  --profile scraper run --rm scraper
```

No separate cronjob or helper script is needed—Stackr executes the job on the
homelab host and logs success/failure alongside deploy events.

### Automatic rollouts

To push new GHCR tags automatically, run Stackr as described in
[`docs/stackr.md`](../../docs/stackr.md) and call it from the GitHub Actions
workflow after images are published. Stackr updates `MX5PARTS_IMAGE_TAG` in
`.env` and executes `./stackr mx5parts update`, so no manual SSH session is
required once the shared token is configured.
