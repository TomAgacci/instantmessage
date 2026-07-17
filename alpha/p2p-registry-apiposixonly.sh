#!/usr/bin/env bash
#
# p2p-registry-api.sh
#
# Endpoints:
# - POST /users/register      → create user with password (hashed)
# - POST /users/auth          → verify password
# - POST /users/reset         → reset password (old → new)
# - POST /presence/heartbeat  → store presence
# - GET  /presence/lookup?uid=XYZ → lookup presence
# - POST /tokens/create       → issue random token for uid
# - POST /tokens/sign         → HMAC-SHA256 sign payload for uid
#
# Files:
#   data/users.log    ts  uid  password_hash  raw_body
#   data/presence.log ts  raw_body
#   data/tokens.log   ts  uid  token
#
# Requires: bash, nc, sha256sum, openssl, awk, sed, grep, base64

PORT="${PORT:-8080}"
DATA_DIR="${DATA_DIR:-./data}"
USERS_FILE="$DATA_DIR/users.log"
PRESENCE_FILE="$DATA_DIR/presence.log"
TOKENS_FILE="$DATA_DIR/tokens.log"

# HMAC secret (for /tokens/sign)
HMAC_SECRET="${HMAC_SECRET:-change-this-secret}"

mkdir -p "$DATA_DIR"
touch "$USERS_FILE" "$PRESENCE_FILE" "$TOKENS_FILE"

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

hash_password() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

find_user_hash() {
  local uid="$1"
  grep -F "$uid" "$USERS_FILE" | tail -n 1 | awk -F'\t' '{print $3}'
}

handle_users_register() {
  local body="$1"
  local ts uid password hashed

  ts="$(date +'%s')"
  password="$(extract_json_field "password" "$body")"
  hashed="$(hash_password "$password")"

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
  hashed="$(hash_password "$password")"

  stored="$(find_user_hash "$uid")"

  if [ "$hashed" = "$stored" ] && [ -n "$stored" ]; then
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

handle_users_reset() {
  local body="$1"
  local uid old_password new_password old_hashed stored new_hashed ts

  uid="$(extract_json_field "uid" "$body")"
  old_password="$(extract_json_field "old_password" "$body")"
  new_password="$(extract_json_field "new_password" "$body")"

  old_hashed="$(hash_password "$old_password")"
  stored="$(find_user_hash "$uid")"

  if [ "$old_hashed" != "$stored" ] || [ -z "$stored" ]; then
    cat <<EOF
HTTP/1.1 403 Forbidden
Content-Type: application/json

{"reset":"fail","reason":"bad_old_password","uid":"$uid"}
EOF
    return
  fi

  new_hashed="$(hash_password "$new_password")"
  ts="$(date +'%s')"

  printf '%s\t%s\t%s\t%s\n' "$ts" "$uid" "$new_hashed" "$body" >> "$USERS_FILE"

  cat <<EOF
HTTP/1.1 200 OK
Content-Type: application/json

{"reset":"ok","uid":"$uid","updated_at":$ts}
EOF
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

generate_token() {
  # 32 bytes hex token
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    dd if=/dev/urandom bs=32 count=1 2>/dev/null | hexdump -v -e '/1 "%02x"'
  fi
}

handle_tokens_create() {
  local body="$1"
  local uid token ts

  uid="$(extract_json_field "uid" "$body")"
  ts="$(date +'%s')"
  token="$(generate_token)"

  printf '%s\t%s\t%s\n' "$ts" "$uid" "$token" >> "$TOKENS_FILE"

  cat <<EOF
HTTP/1.1 200 OK
Content-Type: application/json

{"token":"$token","uid":"$uid","issued_at":$ts}
EOF
}

hmac_sha256() {
  local payload="$1"
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$payload" | openssl dgst -sha256 -hmac "$HMAC_SECRET" | awk '{print $2}'
  else
    # Fallback: not a real HMAC, just SHA256 (for environments without openssl)
    printf '%s%s' "$HMAC_SECRET" "$payload" | sha256sum | awk '{print $1}'
  fi
}

handle_tokens_sign() {
  local body="$1"
  local uid payload sig

  uid="$(extract_json_field "uid" "$body")"
  payload="$(extract_json_field "payload" "$body")"

  sig="$(hmac_sha256 "$payload")"

  cat <<EOF
HTTP/1.1 200 OK
Content-Type: application/json

{"uid":"$uid","payload":"$payload","hmac_sha256":"$sig"}
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
    "POST /users/reset")
      handle_users_reset "$body"
      ;;
    "POST /presence/heartbeat")
      handle_presence_heartbeat "$body"
      ;;
    "POST /tokens/create")
      handle_tokens_create "$body"
      ;;
    "POST /tokens/sign")
      handle_tokens_sign "$body"
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
