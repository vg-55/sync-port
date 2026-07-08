#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# sync-ports.sh — Periodically transfer port scan results to
#                 the main VPS via password-based SCP (sshpass).
# ============================================================
#
# Usage:
#   ./sync-ports.sh -f <file> -h <host> -u <user> -p <pass> [-r <remote_name>] [-d <remote_dir>] [-i <interval_sec>]
#
#   -f   Path to the port-scan file to transfer
#   -h   Main VPS IP / hostname
#   -u   SSH username on the main VPS
#   -p   SSH password (no SSH key required)
#   -r   Remote filename (default: same as local filename)
#        Useful to give each node a unique name, e.g. -r node1-ports.txt
#   -d   Remote destination directory (default: ~/ports/)
#   -i   Transfer interval in seconds (default: 600 = 10 min)
#   -1   One-shot mode — transfer once and exit
#
# Examples:
#   # Transfer every 10 minutes (same name on both ends)
#   ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'mypass'
#
#   # Transfer with a different remote name (node1's results)
#   ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'mypass' -r node1-ports.txt
#
#   # One-shot transfer
#   ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'mypass' -1
#
#   # Custom interval (5 min) + custom remote dir
#   ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'mypass' -d /var/scans/ -i 300
#
# Requirements on the scanning machine:
#   - sshpass must be installed (brew install sshpass / apt install sshpass)
#   - scp must be available
# ============================================================

usage() {
    sed -n 's/^# //p' "$0" | head -30
    exit 0
}

# --- defaults ---
REMOTE_DIR="~/ports/"
INTERVAL=600          # 10 minutes
ONESHOT=false
REMOTE_NAME=""         # defaults to local filename if not set

# --- parse args ---
while getopts "f:h:u:p:r:d:i:1" opt; do
    case "$opt" in
        f) FILE="$OPTARG" ;;
        h) HOST="$OPTARG" ;;
        u) USER="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        r) REMOTE_NAME="$OPTARG" ;;
        d) REMOTE_DIR="$OPTARG" ;;
        i) INTERVAL="$OPTARG" ;;
        1) ONESHOT=true ;;
        *) usage ;;
    esac
done

# --- validate required ---
if [[ -z "${FILE:-}" || -z "${HOST:-}" || -z "${USER:-}" || -z "${PASSWORD:-}" ]]; then
    echo "[!] Missing required arguments (-f, -h, -u, -p)."
    echo ""
    usage
fi

if [[ ! -f "$FILE" ]]; then
    echo "[!] File not found: $FILE"
    exit 1
fi

if ! command -v sshpass &>/dev/null; then
    echo "[!] 'sshpass' is not installed. Install it first:"
    echo "    macOS:  brew install hudochenkov/sshpass/sshpass"
    echo "    Linux:  sudo apt install sshpass"
    exit 1
fi

# --- Ensure remote directory exists ---
ensure_remote_dir() {
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${USER}@${HOST}" "mkdir -p ${REMOTE_DIR}" 2>/dev/null || true
}

# --- Transfer function ---
do_transfer() {
    local filename
    if [[ -n "${REMOTE_NAME:-}" ]]; then
        filename="$REMOTE_NAME"
    else
        filename=$(basename "$FILE")
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Transferring $FILE -> ${USER}@${HOST}:${REMOTE_DIR}${filename}"

    if sshpass -p "$PASSWORD" scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$FILE" "${USER}@${HOST}:${REMOTE_DIR}${filename}"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Transfer complete"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ Transfer FAILED"
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
