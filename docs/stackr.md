## Stackr

Stackr is the Go service under `stackr/cmd/stackrd` that exposes a small HTTP API
for rolling out new stack tags and for running cron-style Compose jobs without
logging into the host. CI/CD pipelines call `POST /deploy` with the stack name
and new image tag; Stackr rewrites the matching key inside `.env` and executes
the deployment using the internal Go stack manager. Services annotated with
`stackr.cron.*` labels are scheduled and executed on the same host, so no
separate cronjobs are required.

For local orchestration/maintenance, use the Go CLI (`stackr`) located at
`stackr/cmd/stackr`. All orchestration operations (CLI, API, cron) now use the
same Go codebase internally. **Note:** `run.sh` is deprecated but kept for
backward compatibility.

### Environment variables

Add the following block to `.env` (or export them before launching Stackr):

```
############### stackr VARS
STACKR_HOST=0.0.0.0                            # Bind interface
STACKR_PORT=9000                               # Listen port
STACKR_TOKEN=supersecret                       # Shared Bearer token used by callers
STACKR_ENV_FILE=.env                           # Optional path override
STACKR_CONFIG_FILE=.stackr.yaml                # Optional path override
STACKR_DOMAIN=stackr.example.com
STACKR_HOST_REPO_ROOT=/home/darthvader/serverconfig  # Host path when using Docker socket
# STACKR_REPO_ROOT=/srv/stackr_repo            # Optional override when containerized
# STACKR_STACKS_DIR=stacks                     # Relative to repo root unless absolute
###############################
```

Non-secret defaults (stack paths, cron conventions, media/backup storage,
deploy metadata) live in `.stackr.yaml`, which is committed to git and reloaded
automatically whenever it changes. Secrets stay in `.env`.

### `.stackr.yaml`

The YAML file `.stackr.yaml` at the repo root centralizes repository-wide defaults:

```yaml
stacks_dir: stacks
cron:
  profile: cron
defaults:
  base_domain: example.local
http:
  base_domain: localhost
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
    args: ["mx5parts","update"]
env:
  global:
    TEST_VAR: foo
  stacks:
    owncloud:
      TRUSTED_DOMAINS: 192.168.1.100,oc.example.com
```

- `stacks_dir`: relative or absolute path to the stack folders. Still overridable
  via `STACKR_STACKS_DIR`.
- `cron.profile`: canonical profile name used for opt-in services.
- `http.base_domain`: used to build `STACKR_PROV_DOMAIN` (e.g., `<stack>.localhost`).
- `paths.pools`: per-stack storage pools surfaced as `STACKR_PROV_POOL_SSD/HDD`.
- `paths.custom`: arbitrary env vars pointing to absolute paths (e.g.,
  `MEDIA_STORAGE`, `STACKR_PATH_MEDIA`, etc.).
- `deploy.<stack>`: optional overrides for Stackr’s deploy API. When omitted,
  Stackr defaults to `<STACK>_IMAGE_TAG` and `stackr <stack> update`.
- `env.global` / `env.stacks.<name>`: inject non-secret env vars either
  globally or scoped to a stack during CLI/API runs.

Set `STACKR_REPO_ROOT` when the binary cannot infer the repository path from its
build location (e.g., when running inside Docker). Leave it empty for
host/systemd usage. When running stackr in a container that uses the Docker
socket to control the host Docker daemon, set `STACKR_HOST_REPO_ROOT` to the
repository path on the host (this is needed because docker compose file paths
must be valid from the host's perspective when using the socket).
`STACKR_STACKS_DIR` points to the directory that contains the stack folders
(`docker-compose.yml` lives under `STACKR_STACKS_DIR/<stack>/`). It defaults to
`stacks` inside the repo.

### Running the service

From the repository root:

```bash
cd /home/darthvader/Projects/serverconfig
go run ./stackr/cmd/stackrd
```

For a long-running instance (e.g., systemd), build a binary:

```bash
go build -o ./bin/stackr ./stackr/cmd/stackrd
./bin/stackr
```

#### Running as a stack

To keep management aligned with the other homelab services, run Stackr through
the dedicated stack:

```bash
./run.sh stackr update
```

This stack builds the container image, bind-mounts the repository at
`/srv/serverconfig`, and shares `/var/run/docker.sock` so `./run.sh` commands hit
the host Docker engine. Traefik routes HTTPS traffic to `${STACKR_DOMAIN}` and
polls `/healthz` for liveness. Treat the Docker socket mount as privileged
access and restrict who can call the token. Stackr watches the entire stacks
directory via `fsnotify`, so updates to any `docker-compose.yml` automatically
reload cron schedules without restarting the API.

Wrap it in a systemd service to keep it running:

```
[Unit]
Description=Stackr API
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/darthvader/Projects/serverconfig
EnvironmentFile=/home/darthvader/Projects/serverconfig/.env
ExecStart=/home/darthvader/Projects/serverconfig/bin/stackr
Restart=always

[Install]
WantedBy=multi-user.target
```

### Request format

```
POST /deploy HTTP/1.1
Host: stackr.example.com
Authorization: Bearer <STACKR_TOKEN>
Content-Type: application/json

{
  "stack": "mx5parts",
  "tag": "v1.4.2-feature-branch"
}
```

Use either the `tag` or `image_tag` field (they are aliases) to set the exact
GHCR tag to deploy. Any Docker tag is accepted, so you can also push branch
builds such as `v1.2.3-feature-branch` or `feature--canary`.

On success Stackr returns `200 OK` and includes the captured stdout from
`./run.sh`. If the rollout fails, Stackr restores the previous env value so the
stack keeps pointing at the last known good tag. Failures reply with `500` and
include the run output for debugging.

### Health checks

`GET /healthz` always responds with `200 OK` and `{"status":"ok"}`. Point
systemd, Traefik, or any other supervisor at this endpoint for a simple liveness
probe when wiring the service into production.

### Container cron

Any stack service can advertise a cron schedule through labels and Stackr will
execute it with the correct environment. Add the schedule label (and optionally
place the service in its own Compose profile) like this:

```
    profiles:
      - scraper
    labels:
      - stackr.cron.schedule=0 1,13 * * *
      - stackr.cron.run_on_deploy=true  # optional: trigger immediately after Stackr starts
```

`stackr.cron.schedule` uses standard 5-field cron syntax (minute hour day
month weekday). When triggered, Stackr executes the service via the internal
Go manager with the stack's environment variables, equivalent to:

```
docker compose --file stacks/<stack>/docker-compose.yml \
  --profile <compose profile, if exactly one is defined> run --rm <service>
```

If the service declares exactly one Compose profile, Stackr automatically adds
`--profile <name>` so the scheduled task can run without being part of the
default stack. Otherwise the flag is omitted. Set
`stackr.cron.run_on_deploy=true` to run the job once immediately (when Stackr
starts) and then continue on the normal schedule. This replaces ad-hoc host
cronjobs (for example the mx5parts scraper) while keeping all scheduling logic
co-located with the Compose definition.

### GitHub Actions integration

Add a job/step to the release workflow that calls Stackr once the new GHCR tag
has been pushed:

```yaml
- name: Deploy mx5parts stack
  if: github.event_name == 'workflow_run'
  env:
    STACKR_ENDPOINT: https://stackr.example.com/deploy
    STACKR_TOKEN: ${{ secrets.MX5PARTS_STACKR_TOKEN }}
  run: |
    curl -sSf -X POST "$STACKR_ENDPOINT" \
      -H "Authorization: Bearer $STACKR_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"stack\":\"mx5parts\",\"tag\":\"${{ steps.vars.outputs.version }}\"}"
```

If releases use semantic tags (`v1.2.3`), pass that tag in the payload. Stackr
updates `MX5PARTS_IMAGE_TAG` in `.env` and then executes the stack update via
the internal Go manager, ensuring Docker pulls the requested GHCR image.
