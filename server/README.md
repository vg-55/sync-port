# Server (Main VPS)

The **receiver** — runs on the main VPS, accepts file uploads from scanning nodes.

## Files

| File | Purpose |
|---|---|
| `webhook-receiver.py` | Write-only HTTP server — accepts POST /upload only |
| `sync-ports-webhook.service` | systemd unit (survives reboot) |

## Quick Start

```bash
# Download
wget -O /root/webhook-receiver.py https://raw.githubusercontent.com/vg-55/sync-port/main/server/webhook-receiver.py
wget -O /etc/systemd/system/sync-ports-webhook.service https://raw.githubusercontent.com/vg-55/sync-port/main/server/sync-ports-webhook.service

# Edit service (set your token)
sudo nano /etc/systemd/system/sync-ports-webhook.service
#   Change: --token YOUR_SECRET_TOKEN

# Install as service
sudo systemctl daemon-reload
sudo systemctl enable --now sync-ports-webhook
sudo systemctl status sync-ports-webhook
```

## API

**Write-only** — no reading, no listing, no directory browsing.

```bash
# Upload a file (the only valid request)
curl -X POST \
  -H "X-Auth-Token: mysecrettoken" \
  -F "file=@/tmp/ports.txt" \
  -F "name=node1-ports.txt" \
  http://VPS_IP:9090/upload

# Response (200): {"ok": true, "file": "node1-ports.txt", "size": 12345, ...}

# Anything else → 403 / 405
```

## CLI Options

```
python3 webhook-receiver.py --token <secret> [--port 9090] [--dir /var/scans] [--bind 0.0.0.0]
```

| Flag | Default | Description |
|---|---|---|
| `--token` | (required) | Shared secret token |
| `--port` | `9090` | Listen port |
| `--dir` | `/var/scans` | Upload directory |
| `--bind` | `0.0.0.0` | Bind address |
