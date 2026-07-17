#!/usr/bin/env bash
#
# p2p-registry-api.sh
#
# Tiny bash HTTP API for a P2P-style registry:
# - POST /users/register      (store user + public_key)
# - POST /presence/heartbeat  (store presence endpoint)
# - GET  /presence/lookup?uid=XYZ (lookup latest presence + key)
#
# This is a toy, file-backed API you can drop into a repo.
# Requires: bash, nc, grep, sed, awk, date

PORT="${PORT:-8080}"
DATA_DIR="${DATA_DIR:-./data}"
USERS_FILE="$DATA_DIR/users.log"
PRESENCE_FILE="$DATA_DIR/presence.log"

mkdir -p "$DATA_DIR"
touch "$USERS_FILE" "$PRESENCE_FILE"

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" >&2
}

url_decode() {
  # Very simple URL decoder (handles %XX and +)
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

parse_query_param() {
  # parse_query_param "uid" "uid=abc&x=1"
  local key="$1"
  local qs="$2"
  echo "$qs" | tr '&' '\n' | awk -F'=' -v k="$key" '$1==k {print $2}'
}

handle_users_register() {
  local body="$1"
  # Expect JSON like:
  # {"public_key":"BASE64_PUBKEY","display_name":"Max"}
  local ts uid
  ts="$(date +'%s')"

  # Generate a simple uid as hash of body + timestamp
  uid="$(printf '%s' "$body$ts" | sha1sum | awk '{print $1}')"

  printf '%s\t%s\t%s\n' "$ts" "$uid" "$body" >> "$USERS_FILE"

  cat <<EOF
HTTP/1.1 200 OK
Content-Type: application/json

{"uid":"$uid","created_at":$ts}
EOF
}

handle_presence_heartbeat() {
  local body="$1"
  # Expect JSON like:
  # {"uid":"user-123","endpoint":{"type":"webrtc","signal_id":"sig-abc"}}
  local ts
  ts="$(date +'%s')"

  printf '%s\t%s\n' "$ts" "$body" >> "$PRESENCE_FILE"

  cat <<EOF
HTTP/1.1 200 OK
Content-Type: application/json

{"status":"ok","server_time":$ts}
EOF
}

handle_presence_lookup() {
  local uid="$1"

  # Find latest presence line containing "uid":"<uid>"
  local line
  line="$(grep -F "\"uid\":\"$uid\"" "$PRESENCE_FILE" | tail -n 1)"

  if [ -z "$line" ]; then
    cat <<EOF
HTTP/1.1 404 Not Found
Content-Type: application/json

{"error":"not_found","uid":"$uid"}
EOF
    return
  fi

  # Extract JSON body (second field)
  local json
  json="$(printf '%s\n' "$line" | awk -F'\t' '{print $2}')"

  cat <<EOF
HTTP/1.1 200 OK
Content-Type: application/json

$json
EOF
}

handle_not_found() {
  cat <<EOF
HTTP/1.1 404 Not Found
Content-Type: application/json

{"error":"not_found"}
EOF
}

handle_request() {
  # Read request line
  local request_line method path proto
  IFS=$' \r\n' read -r method path proto || return

  log "REQ: $method $path"

  # Read headers until blank line, then rest is body
  local headers body line
  headers=""
  while IFS=$'\r\n' read -r line; do
    [ -z "$line" ] && break
    headers+="$line"$'\n'
  done

  # Read remaining as body (nc closes after request)
  body="$(cat)"

  # Route
  case "$method $path" in
    "POST /users/register")
      handle_users_register "$body"
      ;;
    "POST /presence/heartbeat")
      handle_presence_heartbeat "$body"
      ;;
    GET\ /presence/lookup\?*)
      # Extract query string
      local qs raw_uid uid
      qs="${path#*?}"
      raw_uid="$(parse_query_param "uid" "$qs")"
      uid="$(url_decode "$raw_uid")"
      handle_presence_lookup "$uid"
      ;;
    *)
      handle_not_found
      ;;
  esac
}

start_server() {
  log "Starting p2p-registry-api on port $PORT"
  while true; do
    # -l: listen, -p: port, -q 1: quit after 1 second of EOF
    nc -l -p "$PORT" -q 1 | handle_request || true
  done
}

start_server
