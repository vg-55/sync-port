# sync-port

Periodically transfer port scan results from **scanning nodes → main VPS**.

## Folder structure

```
sync-port/
├── client/                    # 🖥️ Runs on scanning nodes
│   ├── sync-ports.sh          #    The transfer script
│   ├── sync-ports.conf        #    Secrets config (chmod 600)
│   ├── sync-ports.service     #    systemd unit
│   └── README.md
│
├── server/                    # ☁️ Runs on the main VPS
│   ├── webhook-receiver.py    #    Write-only HTTP endpoint
│   ├── sync-ports-webhook.service  # systemd unit
│   └── README.md
│
└── README.md                  #    This file
```

## Architecture

```
┌──────────────────┐     HTTP POST /upload      ┌──────────────────┐
│  Scanning Node   │ ──────────────────────────> │    Main VPS      │
│  client/         │   X-Auth-Token: secret      │ server/          │
│  sync-ports.sh   │   file=@ports.txt           │ webhook-receiver │
└──────────────────┘                             └──────────────────┘
```

## Three transfer methods

| # | Method | Node needs | VPS attack surface |
|---|--------|-----------|-------------------|
| 1 | **Webhook (HTTP POST)** | `curl` only | Write-only HTTP endpoint |
| 2 | SSH key | `scp` + key | Full SSH |
| 3 | SSH password | `sshpass` + password | Full SSH |

## Quick start — Webhook (2 minutes, no SSH)

### Main VPS

```bash
wget -O /root/webhook-receiver.py https://raw.githubusercontent.com/vg-55/sync-port/main/server/webhook-receiver.py
python3 /root/webhook-receiver.py --token mysecrettoken --port 9090 --dir /var/scans
```

### Scanning Node

```bash
wget -O sync-ports.sh https://raw.githubusercontent.com/vg-55/sync-port/main/client/sync-ports.sh
chmod +x sync-ports.sh
./sync-ports.sh -f /tmp/ports.txt -w http://VPS_IP:9090/upload -t mysecrettoken -r node1-ports.txt
```

**The node has zero SSH access to the VPS.**

## Docs

- [Client docs →](client/README.md) — setup, config reference, all transfer methods
- [Server docs →](server/README.md) — webhook receiver API, systemd setup

