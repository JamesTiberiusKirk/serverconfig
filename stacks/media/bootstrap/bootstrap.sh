#!/usr/bin/env bash
set -euo pipefail

SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
PROWLARR_URL="http://prowlarr:9696"
BAZARR_URL="http://bazarr:6767"

: "${SONARR_API_KEY:?missing}"
: "${RADARR_API_KEY:?missing}"
: "${PROWLARR_API_KEY:?missing}"
: "${BAZARR_API_KEY:?missing}"

RDT_HOST="rdt-client"
RDT_PORT=6500
RDT_USER="admin"
RDT_PASS="admin"

log() { printf '[bootstrap] %s\n' "$*"; }

wait_for() {
  local name=$1 url=$2 key=$3 path=$4
  log "waiting for $name at $url"
  for _ in $(seq 1 60); do
    if curl -fsS -H "X-Api-Key: $key" "$url$path" >/dev/null 2>&1; then
      log "$name ready"
      return 0
    fi
    sleep 5
  done
  log "$name never came up"
  return 1
}

api() {
  local method=$1 url=$2 key=$3 body=${4:-}
  if [ -n "$body" ]; then
    curl -fsS -X "$method" -H "X-Api-Key: $key" -H "Content-Type: application/json" -d "$body" "$url"
  else
    curl -fsS -X "$method" -H "X-Api-Key: $key" "$url"
  fi
}

# --- Sonarr / Radarr download client (RDT-Client as qBittorrent) ---
add_qbit_client() {
  local app=$1 url=$2 key=$3 cat_field=$4 cat_value=$5
  local existing
  existing=$(api GET "$url/api/v3/downloadclient" "$key" | jq -r '.[] | select(.name=="rdt-client") | .id' || true)
  if [ -n "$existing" ]; then
    log "$app: rdt-client download client already exists, skipping"
    return
  fi
  local payload
  payload=$(jq -n \
    --arg host "$RDT_HOST" --argjson port "$RDT_PORT" \
    --arg user "$RDT_USER" --arg pass "$RDT_PASS" \
    --arg cat_field "$cat_field" --arg cat_value "$cat_value" '{
      enable: true, protocol: "torrent", priority: 1, removeCompletedDownloads: true,
      removeFailedDownloads: true, name: "rdt-client",
      implementation: "QBittorrent", configContract: "QBittorrentSettings",
      fields: [
        {name:"host", value:$host},
        {name:"port", value:$port},
        {name:"useSsl", value:false},
        {name:"urlBase", value:""},
        {name:"username", value:$user},
        {name:"password", value:$pass},
        {name:$cat_field, value:$cat_value},
        {name:"initialState", value:0},
        {name:"sequentialOrder", value:false},
        {name:"firstAndLast", value:false}
      ]
    }')
  api POST "$url/api/v3/downloadclient" "$key" "$payload" >/dev/null
  log "$app: rdt-client added"
}

add_root_folder() {
  local app=$1 url=$2 key=$3 path=$4
  local existing
  existing=$(api GET "$url/api/v3/rootfolder" "$key" | jq -r --arg p "$path" '.[] | select(.path==$p) | .id' || true)
  if [ -n "$existing" ]; then
    log "$app: root folder $path already exists, skipping"
    return
  fi
  api POST "$url/api/v3/rootfolder" "$key" "$(jq -n --arg p "$path" '{path:$p}')" >/dev/null
  log "$app: root folder $path added"
}

# --- Prowlarr applications (so Prowlarr pushes indexers to *arr) ---
add_prowlarr_app() {
  local name=$1 impl=$2 base_url=$3 app_api_key=$4 categories=$5
  local existing
  existing=$(api GET "$PROWLARR_URL/api/v1/applications" "$PROWLARR_API_KEY" | jq -r --arg n "$name" '.[] | select(.name==$n) | .id' || true)
  if [ -n "$existing" ]; then
    log "prowlarr: app $name already exists, skipping"
    return
  fi
  local payload
  payload=$(jq -n \
    --arg name "$name" --arg impl "$impl" \
    --arg base "$base_url" --arg key "$app_api_key" \
    --argjson cats "$categories" '{
      name: $name, syncLevel: "fullSync",
      implementation: $impl, configContract: ($impl + "Settings"),
      fields: [
        {name:"prowlarrUrl", value:"http://prowlarr:9696"},
        {name:"baseUrl", value:$base},
        {name:"apiKey", value:$key},
        {name:"syncCategories", value:$cats}
      ]
    }')
  api POST "$PROWLARR_URL/api/v1/applications" "$PROWLARR_API_KEY" "$payload" >/dev/null
  log "prowlarr: app $name added"
}

# --- Bazarr: point at sonarr + radarr ---
configure_bazarr() {
  log "bazarr: writing sonarr/radarr settings"
  local payload
  payload=$(jq -n \
    --arg sk "$SONARR_API_KEY" --arg rk "$RADARR_API_KEY" '{
      general: { use_sonarr: true, use_radarr: true },
      sonarr: { ip:"sonarr", port:8989, base_url:"/", ssl:false, apikey:$sk, full_update:"Daily" },
      radarr: { ip:"radarr", port:7878, base_url:"/", ssl:false, apikey:$rk, full_update:"Daily" }
    }')
  curl -fsS -X POST -H "X-Api-Key: $BAZARR_API_KEY" -H "Content-Type: application/json" \
    -d "$payload" "$BAZARR_URL/api/system/settings" >/dev/null
  log "bazarr: settings applied"
}

wait_for sonarr   "$SONARR_URL"   "$SONARR_API_KEY"   "/api/v3/system/status"
wait_for radarr   "$RADARR_URL"   "$RADARR_API_KEY"   "/api/v3/system/status"
wait_for prowlarr "$PROWLARR_URL" "$PROWLARR_API_KEY" "/api/v1/system/status"
wait_for bazarr   "$BAZARR_URL"   "$BAZARR_API_KEY"   "/api/system/status"

add_qbit_client    sonarr "$SONARR_URL" "$SONARR_API_KEY" "tvCategory"    "tv-sonarr"
add_qbit_client    radarr "$RADARR_URL" "$RADARR_API_KEY" "movieCategory" "radarr"
add_root_folder    sonarr "$SONARR_URL" "$SONARR_API_KEY" "/media/tv_shows"
add_root_folder    radarr "$RADARR_URL" "$RADARR_API_KEY" "/media/Movies"

add_prowlarr_app Sonarr Sonarr "http://sonarr:8989" "$SONARR_API_KEY" '[5000,5010,5020,5030,5040,5045,5050]'
add_prowlarr_app Radarr Radarr "http://radarr:7878" "$RADARR_API_KEY" '[2000,2010,2020,2030,2040,2045,2050,2060]'

configure_bazarr

log "done"
