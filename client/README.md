# Client (Scanning Node)

The **sender** — runs on every scanning node, periodically uploads port scan results to the main VPS.

## Files

| File | Purpose |
|---|---|
| `sync-ports.sh` | The script — runs the transfer loop |
| `sync-ports.conf` | Config + secrets (chmod 600, read by systemd) |
| `sync-ports.service` | systemd unit (survives reboot) |

## Quick Start

```bash
# Download
wget -O /root/sync-ports.sh  https://raw.githubusercontent.com/vg-55/sync-port/main/client/sync-ports.sh
wget -O /etc/systemd/system/sync-ports.service https://raw.githubusercontent.com/vg-55/sync-port/main/client/sync-ports.service
wget -O /etc/sync-ports.conf https://raw.githubusercontent.com/vg-55/sync-port/main/client/sync-ports.conf
chmod +x /root/sync-ports.sh
chmod 600 /etc/sync-ports.conf

# Edit config
sudo nano /etc/sync-ports.conf

# Install as service
sudo systemctl daemon-reload
sudo systemctl enable --now sync-ports
sudo systemctl status sync-ports
```

## Transfer Methods

| Method | Dependencies | Security |
|---|---|---|
| Webhook (HTTP POST) | `curl` | ⭐⭐⭐ No SSH at all |
| SSH key | `openssh-client` | ⭐⭐ |
| SSH password | `sshpass` | ⭐ |

### Webhook mode (recommended)

```bash
# Just a shared token — no SSH, no keys, no password on the node
./sync-ports.sh -f /tmp/ports.txt -w http://VPS_IP:9090/upload -t mytoken -r node1-ports.txt
```

### SSH key mode

```bash
ssh-keygen -t ed25519 -f ~/.ssh/sync-key -N ""
ssh-copy-id -i ~/.ssh/sync-key.pub root@VPS_IP
./sync-ports.sh -f /tmp/ports.txt -h VPS_IP -k ~/.ssh/sync-key -r node1-ports.txt
```

### Config reference

| Env Variable | CLI | Description |
|---|---|---|
| `SYNC_FILE` | `-f` | Path to the port-scan file |
| `SYNC_WEBHOOK_URL` | `-w` | Webhook URL |
| `SYNC_WEBHOOK_TOKEN` | `-t` | Shared auth token |
| `SYNC_HOST` | `-h` | VPS IP (SSH modes) |
| `SYNC_USER` | `-u` | SSH user (default: root) |
| `SYNC_PASSWORD` | `-p` | SSH password |
| `SYNC_SSH_KEY` | `-k` | SSH key path |
| `SYNC_REMOTE_NAME` | `-r` | Remote filename |
| `SYNC_REMOTE_DIR` | `-d` | Remote dir (default: ~/ports/) |
| `SYNC_INTERVAL` | `-i` | Seconds between transfers (default: 600) |
| — | `-1` | One-shot mode |
