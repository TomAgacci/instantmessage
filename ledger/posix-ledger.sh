#!/bin/sh
LEDGER_FILE="${LEDGER_FILE:-./ledger.log}"

mkdir -p "$(dirname "$LEDGER_FILE")"
touch "$LEDGER_FILE"

hash_str() {
    printf '%s' "$1" | sha256sum | awk '{print $1}'
}

append_entry() {
    payload="$1"
    ts="$(date +'%s')"

    last="$(tail -n 1 "$LEDGER_FILE")"
    if [ -z "$last" ]; then
        index=0
        prev_hash="GENESIS"
    else
        index="$(echo "$last" | awk -F'\t' '{print $1}')"
        index=$((index + 1))
        prev_hash="$(echo "$last" | awk -F'\t' '{print $4}')"
    fi

    entry_str="$index|$ts|$prev_hash|$payload"
    entry_hash="$(hash_str "$entry_str")"

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$index" "$ts" "$prev_hash" "$entry_hash" "$payload" >> "$LEDGER_FILE"

    echo "Appended index=$index hash=$entry_hash"
}

show_ledger() {
    cat "$LEDGER_FILE"
}

case "$1" in
    append) append_entry "$2" ;;
    show)   show_ledger ;;
    *)
        echo "Usage: $0 {append|show}" >&2
        exit 1
        ;;
esac
