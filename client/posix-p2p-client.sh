#!/bin/sh
API_URL="${API_URL:-http://localhost:8080}"

cmd="$1"; shift

case "$cmd" in
    register)
        curl -s -X POST "$API_URL/users/register" \
          -H "Content-Type: application/json" \
          -d "{\"display_name\":\"$1\",\"password\":\"$2\",\"public_key\":\"$3\"}"
        ;;
    auth)
        curl -s -X POST "$API_URL/users/auth" \
          -H "Content-Type: application/json" \
          -d "{\"uid\":\"$1\",\"password\":\"$2\"}"
        ;;
    reset)
        curl -s -X POST "$API_URL/users/reset" \
          -H "Content-Type: application/json" \
          -d "{\"uid\":\"$1\",\"old_password\":\"$2\",\"new_password\":\"$3\"}"
        ;;
    heartbeat)
        curl -s -X POST "$API_URL/presence/heartbeat" \
          -H "Content-Type: application/json" \
          -d "{\"uid\":\"$1\",\"endpoint\":$2}"
        ;;
    lookup)
        curl -s "$API_URL/presence/lookup?uid=$1"
        ;;
    token)
        curl -s -X POST "$API_URL/tokens/create" \
          -H "Content-Type: application/json" \
          -d "{\"uid\":\"$1\"}"
        ;;
    sign)
        curl -s -X POST "$API_URL/tokens/sign" \
          -H "Content-Type: application/json" \
          -d "{\"uid\":\"$1\",\"payload\":\"$2\"}"
        ;;
    *)
        echo "Usage: $0 {register|auth|reset|heartbeat|lookup|token|sign}" >&2
        exit 1
        ;;
esac
