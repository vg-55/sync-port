#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# sync-ports.sh — Periodically transfer port scan results to
#                 the main VPS via SCP.
#
# Supports both SSH key auth (recommended) and password auth.
# ============================================================
#
# All options can be passed via CLI flags OR environment variables:
#
#   CLI Flag  | Env Variable      | Description
#   ----------|-------------------|------------------------------
#   -f        | SYNC_FILE         | Path to port-scan file
#   -h        | SYNC_HOST         | Main VPS IP / hostname
#   -u        | SYNC_USER         | SSH username
#   -p        | SYNC_PASSWORD     | SSH password (optional if using keys)
#   -k        | SYNC_SSH_KEY      | Path to SSH private key (optional)
#   -r        | SYNC_REMOTE_NAME  | Remote filename
#   -d        | SYNC_REMOTE_DIR   | Remote destination dir (default: ~/ports/)
#   -i        | SYNC_INTERVAL     | Transfer interval in seconds (default: 600)
#   -1        | —                 | One-shot mode — transfer once and exit
#
# Examples:
#   # Using SSH key (most secure — no password anywhere)
#   ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -k ~/.ssh/id_rsa -r node1-ports.txt
#
#   # Using password (password passed on CLI — visible in ps output!)
#   ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'mypass' -r node1-ports.txt
#
#   # Using env vars (nothing on CLI, safe with systemd EnvironmentFile)
#   export SYNC_FILE=/tmp/ports.txt SYNC_HOST=10.0.0.1 SYNC_USER=root
#   export SYNC_PASSWORD='mypass'
#   ./sync-ports.sh
#
#   # One-shot transfer
#   ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'mypass' -1
#
# Requirements:
#   - For password auth: sshpass must be installed
#   - For key auth:     just openssh-client (no extra deps)
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
ONESHOT=false
REMOTE_NAME="${SYNC_REMOTE_NAME:-}"

# --- parse CLI args (override env vars) ---
while getopts "f:h:u:p:k:r:d:i:1" opt; do
    case "$opt" in
        f) FILE="$OPTARG" ;;
        h) HOST="$OPTARG" ;;
        u) USER="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        r) REMOTE_NAME="$OPTARG" ;;
        d) REMOTE_DIR="$OPTARG" ;;
        i) INTERVAL="$OPTARG" ;;
        1) ONESHOT=true ;;
        *) usage ;;
    esac
done

# --- validate required ---
if [[ -z "${FILE:-}" || -z "${HOST:-}" ]]; then
    echo "[!] Missing required arguments: -f (file) and -h (host) are required."
    echo "    Use -f/-h flags or set SYNC_FILE / SYNC_HOST env vars."
    echo ""
    usage
fi

if [[ ! -f "$FILE" ]]; then
    echo "[!] File not found: $FILE"
    exit 1
fi

# Determine auth mode
if [[ -n "${SSH_KEY:-}" ]]; then
    AUTH_MODE="key"
    echo "[i] Using SSH key auth: $SSH_KEY"
elif [[ -n "${PASSWORD:-}" ]]; then
    AUTH_MODE="password"
    if ! command -v sshpass &>/dev/null; then
        echo "[!] 'sshpass' is not installed. Install it first:"
        echo "    macOS:  brew install hudochenkov/sshpass/sshpass"
        echo "    Linux:  sudo apt install sshpass"
        echo ""
        echo "    Or use SSH key auth instead: -k ~/.ssh/id_rsa"
        exit 1
    fi
else
    # Try default SSH key
    for key in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa"; do
        if [[ -f "$key" ]]; then
            SSH_KEY="$key"
            AUTH_MODE="key"
            echo "[i] Auto-detected SSH key: $SSH_KEY"
            break
        fi
    done
    if [[ "${AUTH_MODE:-}" != "key" ]]; then
        echo "[!] No auth method configured."
        echo "    Provide -p <password> for password auth, or"
        echo "    Provide -k <key_path> for SSH key auth, or"
        echo "    Set SYNC_PASSWORD / SYNC_SSH_KEY env var."
        exit 1
    fi
fi

# --- Ensure remote directory exists ---
ensure_remote_dir() {
    local ssh_cmd
    ssh_cmd="${USER}@${HOST}"

    if [[ "$AUTH_MODE" == "key" ]]; then
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$ssh_cmd" "mkdir -p ${REMOTE_DIR}" 2>/dev/null || true
    else
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$ssh_cmd" "mkdir -p ${REMOTE_DIR}" 2>/dev/null || true
    fi
}

# --- Transfer function ---
do_transfer() {
    local filename ssh_cmd
    if [[ -n "${REMOTE_NAME:-}" ]]; then
        filename="$REMOTE_NAME"
    else
        filename=$(basename "$FILE")
    fi
    ssh_cmd="${USER}@${HOST}"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Transferring $FILE -> ${ssh_cmd}:${REMOTE_DIR}${filename}"

    local exit_code=0
    if [[ "$AUTH_MODE" == "key" ]]; then
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
}

# ============================================================
# Main
# ============================================================
ensure_remote_dir

if $ONESHOT; then
    do_transfer
    exit 0
fi

echo "============================================"
echo " sync-ports.sh — Periodic Transfer"
echo " Local:     $FILE"
if [[ -n "${REMOTE_NAME:-}" ]]; then
    echo " Remote:    ${USER}@${HOST}:${REMOTE_DIR}${REMOTE_NAME}"
else
    echo " Remote:    ${USER}@${HOST}:${REMOTE_DIR}$(basename "$FILE")"
fi
echo " Interval:  ${INTERVAL}s ($(( INTERVAL / 60 )) min)"
echo "============================================"
echo ""

while true; do
    do_transfer
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sleeping ${INTERVAL}s until next transfer..."
    sleep "$INTERVAL"
done
