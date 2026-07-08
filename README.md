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

## Run in Background

```bash
nohup ./sync-ports.sh -f /tmp/ports.txt -h 10.0.0.1 -u root -p 'pass' > sync.log 2>&1 &
```
