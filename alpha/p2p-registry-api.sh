#!/usr/bin/env bash
#
# p2p-registry-api.sh
#
# Adds password support:
# - POST /users/register  → store user + hashed password
# - POST /users/auth      → verify password
# - POST /presence/heartbeat
# - GET  /presence/lookup?uid=XYZ
#
# Toy API using netcat + log files.

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
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

parse_query_param() {
  local key="$1"
  local qs="$2"
  echo "$qs" | tr '&' '\n' | awk -F'=' -v k="$key" '$1==k {print $2}'
}

extract_json_field() {
  # extract_json_field "password" '{"password":"abc"}'
  echo "$2" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"
}

handle_users_register() {
  local body="$1"
  local ts uid password hashed

  ts="$(date +'%s')"

  password="$(extract_json_field "password" "$body")"
  hashed="$(printf '%s' "$password" | sha256sum | awk '{print $1}')"

  uid="$(printf '%s' "$body$ts" | sha1sum | awk '{print $1}')"

  printf '%s\t%s\t%s\t%s\n' "$ts" "$uid" "$hashed" "$body" >> "$USERS_FILE"

  cat <<EOF
HTTP/1.1 200 OK
Content-Type: application/json

{"uid":"$uid","created_at":$ts}
EOF
}

handle_users_auth() {
  local body="$1"
  local uid password hashed stored

  uid="$(extract_json_field "uid" "$body")"
  password="$(extract_json_field "password" "$body")"
  hashed="$(printf '%s' "$password" | sha256sum | awk '{print $1}')"

  stored="$(grep -F "$uid" "$USERS_FILE" | tail -n 1 | awk -F'\t' '{print $3}')"

  if [ "$hashed" = "$stored" ]; then
    cat <<EOF
HTTP/1.1 200 OK
Content-Type: application/json

{"auth":"ok","uid":"$uid"}
EOF
  else
    cat <<EOF
HTTP/1.1 403 Forbidden
Content-Type: application/json

{"auth":"fail","uid":"$uid"}
EOF
  fi
}

handle_presence_heartbeat() {
  local body="$1"
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
  local line json

  line="$(grep -F "\"uid\":\"$uid\"" "$PRESENCE_FILE" | tail -n 1)"

  if [ -z "$line" ]; then
    cat <<EOF
HTTP/1.1 404 Not Found
Content-Type: application/json

{"error":"not_found","uid":"$uid"}
EOF
    return
  fi

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
  local request_line method path proto headers body line
  IFS=$' \r\n' read -r method path proto || return

  log "REQ: $method $path"

  while IFS=$'\r\n' read -r line; do
    [ -z "$line" ] && break
    headers+="$line"$'\n'
  done

  body="$(cat)"

  case "$method $path" in
    "POST /users/register")
      handle_users_register "$body"
      ;;
    "POST /users/auth")
      handle_users_auth "$body"
      ;;
    "POST /presence/heartbeat")
      handle_presence_heartbeat "$body"
      ;;
    GET\ /presence/lookup\?*)
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
    nc -l -p "$PORT" -q 1 | handle_request || true
  done
}

start_server
