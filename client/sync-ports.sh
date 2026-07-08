#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# sync-ports.sh — Periodically transfer port scan results to
#                 the main VPS.
#
# Supports 3 transfer methods:
#   1. Webhook (HTTP POST)  — recommended, no SSH at all
#   2. SSH key              — scp with key
#   3. SSH password         — scp with sshpass
# ============================================================
#
# All options can be passed via CLI flags OR environment variables:
#
#   CLI Flag  | Env Variable        | Description
#   ----------|---------------------|----------------------------
#   -f        | SYNC_FILE           | Path to port-scan file
#   -h        | SYNC_HOST           | Main VPS IP / hostname
#   -u        | SYNC_USER           | SSH username (default: root)
#   -p        | SYNC_PASSWORD       | SSH password
#   -k        | SYNC_SSH_KEY        | Path to SSH private key
#   -w        | SYNC_WEBHOOK_URL    | Webhook URL (e.g. http://vps:9090/upload)
#   -t        | SYNC_WEBHOOK_TOKEN  | Shared secret for webhook auth
#   -r        | SYNC_REMOTE_NAME    | Remote filename
#   -d        | SYNC_REMOTE_DIR     | Remote dir (default: ~/ports/)
#   -i        | SYNC_INTERVAL       | Interval in seconds (default: 600)
#   -1        | —                   | One-shot mode — transfer once and exit
#
# Examples:
#   # Webhook mode (no SSH at all — just HTTP POST)
#   ./sync-ports.sh -f /tmp/ports.txt -w http://10.0.0.1:9090/upload -t mytoken -r node1-ports.txt
#
#   # SSH key mode
#   ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -k ~/.ssh/id_rsa -r node1-ports.txt
#
#   # SSH password mode
#   ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'mypass' -r node1-ports.txt
#
#   # Env vars only (nothing on CLI, safe with systemd)
#   export SYNC_FILE=/tmp/ports.txt SYNC_WEBHOOK_URL=http://10.0.0.1:9090/upload
#   export SYNC_WEBHOOK_TOKEN=mytoken SYNC_REMOTE_NAME=node1-ports.txt
#   ./sync-ports.sh
#
# Requirements:
#   - Webhook mode:  curl (already on every Linux)
#   - SSH key mode:  openssh-client
#   - SSH pass mode: sshpass + openssh-client
# ============================================================

usage() {
    sed -n 's/^# //p' "$0" | head -30
    exit 0
}

# --- defaults (env vars override) ---
FILE="${SYNC_FILE:-}"
HOST="${SYNC_HOST:-}"
USER="${SYNC_USER:-root}"
PASSWORD="${SYNC_PASSWORD:-}"
SSH_KEY="${SYNC_SSH_KEY:-}"
REMOTE_DIR="${SYNC_REMOTE_DIR:-~/ports/}"
INTERVAL="${SYNC_INTERVAL:-600}"
WEBHOOK_URL="${SYNC_WEBHOOK_URL:-}"
WEBHOOK_TOKEN="${SYNC_WEBHOOK_TOKEN:-}"
ONESHOT=false
REMOTE_NAME="${SYNC_REMOTE_NAME:-}"

# --- parse CLI args (override env vars) ---
while getopts "f:h:u:p:k:w:t:r:d:i:1" opt; do
    case "$opt" in
        f) FILE="$OPTARG" ;;
        h) HOST="$OPTARG" ;;
        u) USER="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        w) WEBHOOK_URL="$OPTARG" ;;
        t) WEBHOOK_TOKEN="$OPTARG" ;;
        r) REMOTE_NAME="$OPTARG" ;;
        d) REMOTE_DIR="$OPTARG" ;;
        i) INTERVAL="$OPTARG" ;;
        1) ONESHOT=true ;;
        *) usage ;;
    esac
done

# --- validate required ---
if [[ -z "${FILE:-}" ]]; then
    echo "[!] Missing required argument: -f (file)."
    echo "    Use -f flag or set SYNC_FILE env var."
    echo ""
    usage
fi

if [[ ! -f "$FILE" ]]; then
    echo "[!] File not found: $FILE"
    exit 1
fi

# --- Determine transfer mode ---
TRANSFER_MODE=""   # webhook | key | password

if [[ -n "${WEBHOOK_URL:-}" ]]; then
    TRANSFER_MODE="webhook"
    if ! command -v curl &>/dev/null; then
        echo "[!] 'curl' is required for webhook mode."
        exit 1
    fi
    if [[ -z "${WEBHOOK_TOKEN:-}" ]]; then
        echo "[!] Webhook token required (-t or SYNC_WEBHOOK_TOKEN)."
        exit 1
    fi
    echo "[i] Using webhook mode: $WEBHOOK_URL"

elif [[ -n "${SSH_KEY:-}" ]]; then
    if [[ -z "${HOST:-}" ]]; then
        echo "[!] Missing -h (host) for SSH key mode."
        exit 1
    fi
    TRANSFER_MODE="key"
    echo "[i] Using SSH key auth: $SSH_KEY"

elif [[ -n "${PASSWORD:-}" ]]; then
    if [[ -z "${HOST:-}" ]]; then
        echo "[!] Missing -h (host) for SSH password mode."
        exit 1
    fi
    TRANSFER_MODE="password"
    if ! command -v sshpass &>/dev/null; then
        echo "[!] 'sshpass' is not installed. Install it first:"
        echo "    Linux:  sudo apt install sshpass"
        echo "    Or use webhook mode (-w) or SSH key mode (-k)."
        exit 1
    fi

else
    # Try default SSH key (only if -w not set)
    if [[ -z "${WEBHOOK_URL:-}" ]]; then
        for key in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa"; do
            if [[ -f "$key" ]]; then
                SSH_KEY="$key"
                TRANSFER_MODE="key"
                echo "[i] Auto-detected SSH key: $SSH_KEY"
                break
            fi
        done
    fi
    if [[ -z "${TRANSFER_MODE:-}" ]]; then
        echo "[!] No transfer method configured."
        echo "    Webhook:  -w <url> -t <token>"
        echo "    SSH key:  -h <host> -k <key>"
        echo "    Password: -h <host> -u <user> -p <pass>"
        exit 1
    fi
fi

# --- Ensure remote directory exists (SSH modes only) ---
ensure_remote_dir_ssh() {
    local ssh_cmd
    ssh_cmd="${USER}@${HOST}"

    if [[ "$TRANSFER_MODE" == "key" ]]; then
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$ssh_cmd" "mkdir -p ${REMOTE_DIR}" 2>/dev/null || true
    else
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$ssh_cmd" "mkdir -p ${REMOTE_DIR}" 2>/dev/null || true
    fi
}

# --- Transfer function ---
do_transfer() {
    local filename
    if [[ -n "${REMOTE_NAME:-}" ]]; then
        filename="$REMOTE_NAME"
    else
        filename=$(basename "$FILE")
    fi

    local exit_code=0

    if [[ "$TRANSFER_MODE" == "webhook" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] POST $FILE -> $WEBHOOK_URL (as $filename)"

        # --write-out '\n%{http_code}' appends status code on last line
        local http_code
        http_code=$(curl -s -o /dev/null -w '%{http_code}' \
            -X POST \
            -H "X-Auth-Token: $WEBHOOK_TOKEN" \
            -F "file=@${FILE}" \
            -F "name=${filename}" \
            "$WEBHOOK_URL") || exit_code=$?

        if [[ "$http_code" == "200" ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Transfer complete (HTTP $http_code)"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ Transfer FAILED (HTTP $http_code)"
        fi

    else
        # SSH modes
        local ssh_cmd="${USER}@${HOST}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SCP $FILE -> ${ssh_cmd}:${REMOTE_DIR}${filename}"

        if [[ "$TRANSFER_MODE" == "key" ]]; then
            scp -i "$SSH_KEY" \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                "$FILE" "${ssh_cmd}:${REMOTE_DIR}${filename}" || exit_code=$?
        else
            sshpass -p "$PASSWORD" scp \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                "$FILE" "${ssh_cmd}:${REMOTE_DIR}${filename}" || exit_code=$?
        fi

        if [[ $exit_code -eq 0 ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Transfer complete"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ Transfer FAILED (exit code: $exit_code)"
        fi
    fi
}

# ============================================================
# Main
# ============================================================
if [[ "$TRANSFER_MODE" != "webhook" ]]; then
    ensure_remote_dir_ssh
fi

if $ONESHOT; then
    do_transfer
    exit 0
fi

echo "============================================"
echo " sync-ports.sh — Periodic Transfer"
echo " Local:     $FILE"
if [[ "$TRANSFER_MODE" == "webhook" ]]; then
    echo " Method:    Webhook (HTTP POST)"
    if [[ -n "${REMOTE_NAME:-}" ]]; then
        echo " Remote:    ${WEBHOOK_URL} (as ${REMOTE_NAME})"
    else
        echo " Remote:    ${WEBHOOK_URL}"
    fi
else
    echo " Method:    SCP (${TRANSFER_MODE})"
    if [[ -n "${REMOTE_NAME:-}" ]]; then
        echo " Remote:    ${USER}@${HOST}:${REMOTE_DIR}${REMOTE_NAME}"
    else
        echo " Remote:    ${USER}@${HOST}:${REMOTE_DIR}$(basename "$FILE")"
    fi
fi
echo " Interval:  ${INTERVAL}s ($(( INTERVAL / 60 )) min)"
echo "============================================"
echo ""

while true; do
    do_transfer
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sleeping ${INTERVAL}s until next transfer..."
    sleep "$INTERVAL"
done
