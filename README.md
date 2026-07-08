# sync-ports.sh

Periodically transfer port scan result files to the main VPS via SCP.
Supports both **SSH key auth** (recommended) and **password auth** via sshpass.

## 🔒 Secure by Default

All settings can be passed via **environment variables** — keeping secrets out of CLI flags,
out of `ps` output, and out of the service file.

| Env Variable | CLI Flag | Description |
|---|---|---|
| `SYNC_FILE` | `-f` | Path to the port-scan file |
| `SYNC_HOST` | `-h` | Main VPS IP / hostname |
| `SYNC_USER` | `-u` | SSH username (default: `root`) |
| `SYNC_PASSWORD` | `-p` | SSH password (only for password auth) |
| `SYNC_SSH_KEY` | `-k` | Path to SSH private key (recommended) |
| `SYNC_REMOTE_NAME` | `-r` | Remote filename |
| `SYNC_REMOTE_DIR` | `-d` | Remote dir (default: `~/ports/`) |
| `SYNC_INTERVAL` | `-i` | Interval in seconds (default: `600`) |
| — | `-1` | One-shot mode |

## Quick Start

```bash
# 1. Download the script
wget -O sync-ports.sh https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.sh
chmod +x sync-ports.sh

# 2a. SSH KEY auth (recommended — no password anywhere)
ssh-keygen -t ed25519 -f ~/.ssh/sync-key -N ""
ssh-copy-id -i ~/.ssh/sync-key.pub root@<MAIN_VPS_IP>
./sync-ports.sh -f /tmp/ports.txt -h <MAIN_VPS_IP> -k ~/.ssh/sync-key -r node1-ports.txt

# 2b. PASSWORD auth (needs sshpass)
sudo apt install sshpass
./sync-ports.sh -f /tmp/ports.txt -h <MAIN_VPS_IP> -u root -p '<PASSWORD>' -r node1-ports.txt
```

## Examples

```bash
# SSH key auth — nothing sensitive on CLI
./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.5 -k ~/.ssh/id_rsa -r node1-ports.txt

# Env vars only — nothing on CLI at all (safe with systemd)
SYNC_FILE=/tmp/ports.txt SYNC_HOST=10.0.0.5 SYNC_USER=root \
    SYNC_PASSWORD='secret' SYNC_REMOTE_NAME=node1-ports.txt \
    ./sync-ports.sh

# Every 5 minutes, different remote dir
./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.5 -u ubuntu -p 'pass' -d /home/ubuntu/scans/ -i 300

# One-shot only
./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.5 -u root -p 'pass' -1
```

## Run as a Background Service (survives SSH disconnect & reboot)

You can't keep an SSH terminal open forever. Here are 3 ways to keep the script running permanently:

---

### Method 1: `nohup` + `disown` (quick, survives logout only)

```bash
nohup ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'pass' -r node1-ports.txt > sync.log 2>&1 &
disown
```

⚠️ Won't survive a reboot — you'll need to restart it manually.

---

### Method 2: `screen` (survives logout, reattachable)

```bash
# Start a named screen session
screen -dmS sync-ports ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'pass' -r node1-ports.txt

# Reattach to see logs
screen -r sync-ports

# Detach with: Ctrl+A, then D
```

⚠️ Also won't survive a reboot.

---

## 🔒 Secure systemd Deployment (no secrets in service file)

The IP and password are stored in `/etc/sync-ports.conf` with `chmod 600` — only readable by root.
The service file and script contain zero secrets.

```bash
# 1. Download everything
wget -O /root/sync-ports.sh  https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.sh
wget -O /etc/systemd/system/sync-ports.service https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.service
wget -O /etc/sync-ports.conf https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.conf
chmod +x /root/sync-ports.sh

# 2. Lock down the secrets file (root-only)
chmod 600 /etc/sync-ports.conf

# ============================================================
# 3a. SSH KEY approach (recommended — no password at all)
# ============================================================
ssh-keygen -t ed25519 -f /root/.ssh/sync-key -N ""
ssh-copy-id -i /root/.ssh/sync-key.pub root@<MAIN_VPS_IP>
# Now edit /etc/sync-ports.conf and uncomment SYNC_SSH_KEY

# ============================================================
# 3b. PASSWORD approach (password in /etc/sync-ports.conf)
# ============================================================
sudo apt install sshpass
# Edit /etc/sync-ports.conf and set SYNC_PASSWORD

# 4. Edit the config with your values
sudo nano /etc/sync-ports.conf
#   SYNC_HOST=YOUR_VPS_IP
#   SYNC_REMOTE_NAME=node1-ports.txt
#   SYNC_SSH_KEY=/root/.ssh/sync-key   (if using keys)
#   OR
#   SYNC_PASSWORD=YOUR_PASSWORD        (if using password)

# 5. Enable & start
sudo systemctl daemon-reload
sudo systemctl enable --now sync-ports

# 6. Verify
sudo systemctl status sync-ports
sudo journalctl -u sync-ports -f
```

---

## Deploy to a Node (one-liner)

No need to clone the whole repo — just grab the script:

```bash
# Download + make executable in one go
wget -O sync-ports.sh https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.sh && chmod +x sync-ports.sh

# Or with curl
curl -sSL -o sync-ports.sh https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.sh && chmod +x sync-ports.sh
```
