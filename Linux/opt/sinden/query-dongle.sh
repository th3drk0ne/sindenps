#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-/dev/ttyGCON45S_0}"
BAUD="${2:-57600}"
QUERY="${3:-I}"

BOOT_WAIT="${BOOT_WAIT:-5}"
READ_TIMEOUT="${READ_TIMEOUT:-2}"
RETRIES="${RETRIES:-8}"

log() { echo "[INFO] $*" >&2; }
err() { echo "[ERROR] $*" >&2; }

cleanup() {
    exec 3>&- 2>/dev/null || true
}
trap cleanup EXIT

# ? Wait until device is ACTUALLY usable (fixes boot issue)
wait_for_port() {
    log "Waiting for $PORT..."

    for ((i=0; i<40; i++)); do
        if [[ -e "$PORT" ]]; then
            if stty -F "$PORT" "$BAUD" >/dev/null 2>&1; then
                log "Port is ready"
                return 0
            fi
        fi
        sleep 0.5
    done

    err "Port never became ready"
    exit 1
}

# ? Reset USB serial state (very important on boot)
reset_port() {
    log "Resetting port"

    exec 9<> "$PORT" || return
    sleep 0.3
    exec 9>&-
}

configure_port() {
    stty -F "$PORT" "$BAUD" raw -echo -hupcl min 0 time 5
}

open_port() {
    exec 3<> "$PORT"
}

flush_input() {
    timeout 0.3 cat <&3 > /dev/null 2>&1 || true
}

send_query() {
    printf "%s\n" "$QUERY" >&3
    sleep 0.05
}

read_response() {
    local end=$((SECONDS + READ_TIMEOUT))
    local buf=""
    local char=""

    while (( SECONDS < end )); do
        if read -t 0.2 -u 3 -r -n 1 char; then
            buf+="$char"
            [[ "$char" == $'\n' ]] && break
        fi
    done

    printf "%s" "$buf"
}

main() {
    log "Starting serial query"
    log "PORT=$PORT BAUD=$BAUD"

    # ? critical boot fixes
    wait_for_port
    reset_port

    configure_port
    open_port

    log "Allowing device boot (${BOOT_WAIT}s)"
    sleep "$BOOT_WAIT"

    flush_input

    # ? robust retry loop
    for ((i=1; i<=RETRIES; i++)); do
        log "Attempt $i/$RETRIES"

        send_query
        RESPONSE="$(read_response)"

        if [[ -n "$RESPONSE" ]]; then
            log "? Success"
            echo "$RESPONSE"
            exit 0
        fi

        sleep 0.5
    done

    err "? No response after $RETRIES attempts"
    exit 1
}

main "$@"