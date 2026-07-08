# sync-ports.sh + webhook receiver

Periodically transfer port scan results from **scanning nodes → main VPS**.

Three transfer methods, ranked by security:

| # | Method | Node needs | VPS attack surface |
|---|--------|-----------|-------------------|
| 1 | **Webhook (HTTP POST)** | `curl` only | Write-only HTTP endpoint |
| 2 | SSH key | `scp` + key | Full SSH |
| 3 | SSH password | `sshpass` + password | Full SSH |

**Webhook mode = the node has zero SSH access to the VPS.** It just POSTs the file to a single `/upload` endpoint that cannot read, list, or execute anything.

---

## Architecture

```
┌──────────────────┐     HTTP POST /upload      ┌──────────────────┐
│  Scanning Node   │ ──────────────────────────> │    Main VPS      │
│  sync-ports.sh   │   X-Auth-Token: secret      │ webhook-receiver │
│  (curl upload)   │   file=@ports.txt           │ (write-only)     │
└──────────────────┘                             └──────────────────┘
```

---

## Env Variable Reference

All settings can be env vars — keep secrets out of CLI and `ps` output.

| Env Variable | CLI | Description |
|---|---|---|
| `SYNC_FILE` | `-f` | Path to the port-scan file |
| `SYNC_WEBHOOK_URL` | `-w` | Webhook URL (e.g. `http://vps:9090/upload`) |
| `SYNC_WEBHOOK_TOKEN` | `-t` | Shared secret for webhook auth |
| `SYNC_HOST` | `-h` | Main VPS IP (SSH modes only) |
| `SYNC_USER` | `-u` | SSH username (default: `root`) |
| `SYNC_PASSWORD` | `-p` | SSH password |
| `SYNC_SSH_KEY` | `-k` | Path to SSH private key |
| `SYNC_REMOTE_NAME` | `-r` | Remote filename |
| `SYNC_REMOTE_DIR` | `-d` | Remote dir (default: `~/ports/`) |
| `SYNC_INTERVAL` | `-i` | Interval in seconds (default: `600`) |
| — | `-1` | One-shot mode |

## 🚀 Quick Start — Webhook (recommended, 2 minutes)

### On the MAIN VPS (receiver)

```bash
# 1. Download the receiver
wget -O /root/webhook-receiver.py https://raw.githubusercontent.com/vg-55/sync-port/main/webhook-receiver.py

# 2. Start it (systemd recommended — see below)
python3 /root/webhook-receiver.py --token mysecrettoken --port 9090 --dir /var/scans
```

### On the SCANNING NODE (sender)

```bash
# 1. Download the script
wget -O sync-ports.sh https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.sh
chmod +x sync-ports.sh

# 2. Run (no SSH, no keys, no password on the node — just a shared token)
./sync-ports.sh -f /tmp/ports.txt -w http://<MAIN_VPS_IP>:9090/upload -t mysecrettoken -r node1-ports.txt
```

That's it. The node has **zero SSH access** to the VPS.

---

## Quick Start — SSH Key (if you prefer SSH)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/sync-key -N ""
ssh-copy-id -i ~/.ssh/sync-key.pub root@<MAIN_VPS_IP>
./sync-ports.sh -f /tmp/ports.txt -h <MAIN_VPS_IP> -k ~/.ssh/sync-key -r node1-ports.txt
```

## Quick Start — SSH Password (least recommended)

```bash
sudo apt install sshpass
./sync-ports.sh -f /tmp/ports.txt -h <MAIN_VPS_IP> -u root -p '<PASSWORD>' -r node1-ports.txt
```

---

## Examples

```bash
# Webhook — one-shot
./sync-ports.sh -f /tmp/ports.txt -w http://10.0.0.1:9090/upload -t mytoken -r node1-ports.txt -1

# SSH key — every 5 min, custom dir
./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.5 -k ~/.ssh/id_rsa -r node1-ports.txt -d /var/scans/ -i 300

# Env vars only — nothing on CLI (safe with systemd)
export SYNC_FILE=/tmp/ports.txt SYNC_WEBHOOK_URL=http://10.0.0.1:9090/upload
export SYNC_WEBHOOK_TOKEN=mytoken SYNC_REMOTE_NAME=node1-ports.txt
./sync-ports.sh
```

---

## 🔒 Secure systemd Deployment — Webhook (no SSH at all)

### Main VPS: webhook receiver (survives reboot)

```bash
# 1. Download receiver + service
wget -O /root/webhook-receiver.py https://raw.githubusercontent.com/vg-55/sync-port/main/webhook-receiver.py
wget -O /etc/systemd/system/sync-ports-webhook.service https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports-webhook.service

# 2. Edit the service with your token + port
sudo nano /etc/systemd/system/sync-ports-webhook.service
#   Change: --token YOUR_SECRET_TOKEN

# 3. Enable & start
sudo systemctl daemon-reload
sudo systemctl enable --now sync-ports-webhook

# 4. Verify
sudo systemctl status sync-ports-webhook
sudo journalctl -u sync-ports-webhook -f
```

### Scanning Node: sender (survives reboot)

```bash
# 1. Download script + service + config
wget -O /root/sync-ports.sh  https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.sh
wget -O /etc/systemd/system/sync-ports.service https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.service
wget -O /etc/sync-ports.conf https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.conf
chmod +x /root/sync-ports.sh
chmod 600 /etc/sync-ports.conf

# 2. Edit the config (webhook mode — no SSH fields needed)
sudo nano /etc/sync-ports.conf
#   Uncomment and set:
#     SYNC_WEBHOOK_URL=http://<MAIN_VPS_IP>:9090/upload
#     SYNC_WEBHOOK_TOKEN=mysecrettoken

# 3. Enable & start
sudo systemctl daemon-reload
sudo systemctl enable --now sync-ports

# 4. Verify
sudo systemctl status sync-ports
sudo journalctl -u sync-ports -f
```

### Webhook Receiver API

The receiver is **write-only** — no reading, no listing, no execution:

```bash
# Upload a file (the only valid request)
curl -X POST \
  -H "X-Auth-Token: mysecrettoken" \
  -F "file=@/tmp/ports.txt" \
  -F "name=node1-ports.txt" \
  http://<VPS_IP>:9090/upload

# Response: {"ok": true, "file": "node1-ports.txt", "size": 12345, "timestamp": "..."}

# Any GET / HEAD / other path → 405 or 404
```

---

## Deploy to a Node (one-liner)

```bash
# Webhook mode — download script + make executable
wget -O sync-ports.sh https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.sh && chmod +x sync-ports.sh

# Or with curl
curl -sSL -o sync-ports.sh https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.sh && chmod +x sync-ports.sh
```
