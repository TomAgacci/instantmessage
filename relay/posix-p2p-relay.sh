#!/bin/sh
LISTEN_PORT="$1"
TARGET_HOST="$2"
TARGET_PORT="$3"

if [ -z "$LISTEN_PORT" ] || [ -z "$TARGET_HOST" ] || [ -z "$TARGET_PORT" ]; then
    echo "Usage: $0 <listen_port> <target_host> <target_port>" >&2
    exit 1
fi

echo "Relay listening on $LISTEN_PORT -> $TARGET_HOST:$TARGET_PORT" >&2

while true; do
    nc -l -p "$LISTEN_PORT" | nc "$TARGET_HOST" "$TARGET_PORT"
done
