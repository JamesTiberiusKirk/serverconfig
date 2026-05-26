#!/usr/bin/env bash
# Per-stack pre-OIDC-migration backup.
# Runs on the target server. Sources repo .env for DB creds.
# Output: $BACKUP_ROOT/migrations/<stack>/<UTC timestamp>/
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <stack|all>

Stacks:
  owncloud   mariadb-dump + tar of data dir (live, --single-transaction)
  immich     pg_dump of metadata DB (photo assets NOT backed up)
  jellyfin   stop -> tar config dir -> start
  grafana    stop -> tar data dir -> start
  portainer  stop -> tar data dir -> start
  all        runs all of the above with a shared timestamp

Overrides via env:
  BACKUP_ROOT  (default: /mnt/16tb/stack_volumes_backup)
  SSD_POOL     (default: /mnt/ssd/stack_volumes)
  HDD_POOL     (default: /mnt/16tb/stack_volumes)
EOF
  exit 1
}

[ $# -eq 1 ] || usage
STACK="$1"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$REPO_ROOT/.env" ] || { echo "missing $REPO_ROOT/.env" >&2; exit 1; }
set -a; . "$REPO_ROOT/.env"; set +a

BACKUP_ROOT="${BACKUP_ROOT:-/mnt/16tb/stack_volumes_backup}"
SSD_POOL="${SSD_POOL:-/mnt/ssd/stack_volumes}"
HDD_POOL="${HDD_POOL:-/mnt/16tb/stack_volumes}"

TS="$(date -u +%Y-%m-%d_%H%M%SZ)"
ALL_STACKS=(owncloud immich jellyfin grafana portainer)

log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

STOPPED=()
cleanup() {
  for c in "${STOPPED[@]:-}"; do
    docker start "$c" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

container_for() {
  docker ps -aq \
    --filter "label=com.docker.compose.project=$1" \
    --filter "label=com.docker.compose.service=$2" \
    | head -1
}

snapshot_dir() {
  local src="$1" dest="$2" name="$3"
  if [ ! -d "$src" ]; then
    log "skip $src (not found)"
    return
  fi
  log "tar.gz $src -> $name.tar.gz"
  tar -C "$(dirname "$src")" -czf "$dest/$name.tar.gz" "$(basename "$src")"
}

with_stopped() {
  local container="$1"; shift
  log "docker stop $container"
  docker stop "$container" >/dev/null
  STOPPED+=("$container")
  "$@"
  log "docker start $container"
  docker start "$container" >/dev/null
}

backup_stack() {
  local stack="$1"
  local dest="$BACKUP_ROOT/migrations/$stack/$TS"
  mkdir -p "$dest"

  case "$stack" in
    owncloud)
      : "${OWNCLOUD_DB_USERNAME:?missing in .env}"
      : "${OWNCLOUD_DB_PASSWORD:?missing in .env}"
      : "${OWNCLOUD_DB_NAME:?missing in .env}"
      log "mariadb-dump $OWNCLOUD_DB_NAME"
      docker exec owncloud_mariadb \
        mariadb-dump --single-transaction --routines --triggers \
        -u"$OWNCLOUD_DB_USERNAME" -p"$OWNCLOUD_DB_PASSWORD" \
        "$OWNCLOUD_DB_NAME" \
        | gzip > "$dest/owncloud.sql.gz"
      snapshot_dir "$HDD_POOL/owncloud/data" "$dest" data
      ;;

    immich)
      : "${IMMICH_DB_USERNAME:?missing in .env}"
      : "${IMMICH_DB_PASSWORD:?missing in .env}"
      : "${IMMICH_DB_DATABASE_NAME:?missing in .env}"
      log "pg_dump $IMMICH_DB_DATABASE_NAME"
      docker exec -e PGPASSWORD="$IMMICH_DB_PASSWORD" immich_postgres \
        pg_dump -Fc -U "$IMMICH_DB_USERNAME" "$IMMICH_DB_DATABASE_NAME" \
        > "$dest/immich.pgdump"
      log "photo assets NOT backed up (OIDC migration doesn't touch them)"
      ;;

    jellyfin)
      with_stopped jellyfin snapshot_dir "$SSD_POOL/media/jellyfin/config" "$dest" jellyfin-config
      ;;

    grafana)
      with_stopped grafana snapshot_dir "$SSD_POOL/monitoring/grafana" "$dest" grafana-data
      ;;

    portainer)
      local cid
      cid="$(container_for portainer portainer)"
      [ -n "$cid" ] || { echo "portainer container not found" >&2; return 1; }
      with_stopped "$cid" snapshot_dir "$SSD_POOL/portainer/data" "$dest" portainer-data
      ;;

    *)
      echo "unknown stack: $stack" >&2
      return 1
      ;;
  esac

  log "$stack done -> $dest"
  ls -lh "$dest"
}

if [ "$STACK" = "all" ]; then
  for s in "${ALL_STACKS[@]}"; do
    log "=== $s ==="
    backup_stack "$s"
  done
  log "ALL DONE — shared timestamp: $TS"
else
  backup_stack "$STACK"
fi
