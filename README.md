# sync-ports.sh

Periodically transfer port scan result files to the main VPS using **password-based SCP** (no SSH keys needed).

## Quick Start

```bash
# 1. Install sshpass (one-time)
# macOS:
brew install hudochenkov/sshpass/sshpass
# Linux:
sudo apt install sshpass

# 2. Make executable
chmod +x sync-ports.sh

# 3. Run (transfers every 10 min)
./sync-ports.sh -f /path/to/ports.txt -h <MAIN_VPS_IP> -u <SSH_USER> -p '<PASSWORD>'
```

## Usage

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-f` | Yes | — | Path to the port-scan file |
| `-h` | Yes | — | Main VPS IP / hostname |
| `-u` | Yes | — | SSH username |
| `-p` | Yes | — | SSH password |
| `-r` | No | local filename | Remote filename (give each node a unique name) |
| `-d` | No | `~/ports/` | Remote destination directory |
| `-i` | No | `600` | Transfer interval in seconds |
| `-1` | No | — | One-shot: transfer once and exit |

## Examples

```bash
# Every 10 minutes (same name on both ends)
./sync-ports.sh -f /tmp/scan-results.txt -h 192.168.1.100 -u root -p 'secret123'

# Different name on main VPS (e.g. identify which node sent it)
./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.5 -u ubuntu -p 'mypass' -r node1-ports.txt

# Every 5 minutes, different remote dir
./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.5 -u ubuntu -p 'mypass' -d /home/ubuntu/scans/ -i 300

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

### Method 3: `systemd` (✅ survives logout, reboot, crashes — best option)

```bash
# 1. Download the systemd service template
wget -O /etc/systemd/system/sync-ports.service https://raw.githubusercontent.com/vg-55/sync-port/main/sync-ports.service

# 2. Edit it with your actual values
sudo nano /etc/systemd/system/sync-ports.service
#   Change: -f /tmp/ports.txt -h YOUR_VPS_IP -u YOUR_USER -p 'YOUR_PASS' -r node1-ports.txt
#   Change: -i 600 to whatever interval you want

# 3. Enable & start (auto-starts on boot!)
sudo systemctl daemon-reload
sudo systemctl enable sync-ports
sudo systemctl start sync-ports

# 4. Check status / logs
sudo systemctl status sync-ports
sudo journalctl -u sync-ports -f        # live logs
sudo journalctl -u sync-ports -n 50     # last 50 lines
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
