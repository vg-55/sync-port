#!/usr/bin/env python3
"""
webhook-receiver.py — Write-only file upload webhook for the MAIN VPS.

Receives port scan files from scanning nodes via HTTP POST.
Nodes have NO SSH access — they just POST the file + a shared secret.

Start:
    python3 webhook-receiver.py --token mysecrettoken --port 9090 --dir /var/scans

    # Background (systemd recommended — see sync-ports-webhook.service)
    nohup python3 webhook-receiver.py --token mysecrettoken --port 9090 --dir /var/scans > /var/log/webhook.log 2>&1 &

Node pushes to it:
    curl -X POST -H "X-Auth-Token: mysecrettoken" -F "file=@/tmp/ports.txt" -F "name=node1-ports.txt" http://MAIN_VPS_IP:9090/upload
"""

import argparse
import os
import sys
import hashlib
import hmac
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler


UPLOAD_DIR = None
AUTH_TOKEN = None


class WebhookHandler(BaseHTTPRequestHandler):
    """Write-only handler: accepts POST /upload, rejects everything else."""

    def do_GET(self):
        """All GET requests return 405 — no reading allowed."""
        self._send_json(405, {"error": "GET not allowed. This is a write-only endpoint. Use POST /upload."})

    def do_HEAD(self):
        self._send_json(405, {"error": "HEAD not allowed."})

    def do_POST(self):
        if self.path != "/upload":
            self._send_json(404, {"error": "Not found. Only /upload is available."})
            return

        # Auth check
        token = self.headers.get("X-Auth-Token", "")
        if not hmac.compare_digest(token, AUTH_TOKEN):
            self._send_json(403, {"error": "Invalid or missing auth token."})
            self._log("AUTH FAILED from %s", self.client_address[0])
            return

        # Parse multipart form
        content_type = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in content_type:
            self._send_json(400, {"error": "Expected multipart/form-data."})
            return

        try:
            form = self._parse_multipart(content_type)
        except Exception as e:
            self._send_json(400, {"error": f"Bad request: {e}"})
            return

        if "file" not in form:
            self._send_json(400, {"error": "Missing 'file' field."})
            return

        filename = form.get("name", form.get("file", ["unnamed.txt"])[0] if isinstance(form.get("name"), list) else "unnamed.txt")
        if isinstance(filename, list):
            filename = filename[0]

        filedata = form["file"]
        if isinstance(filedata, list):
            filedata = filedata[0]

        # Security: sanitize filename (no path traversal)
        filename = os.path.basename(filename)
        if not filename or filename in (".", ".."):
            filename = "uploaded.txt"

        # Write to disk
        dest = os.path.join(UPLOAD_DIR, filename)
        try:
            with open(dest, "wb") as f:
                f.write(filedata)
        except OSError as e:
            self._send_json(500, {"error": f"Failed to write file: {e}"})
            return

        size = len(filedata)
        self._log("RECEIVED %s (%d bytes) from %s", filename, size, self.client_address[0])
        self._send_json(200, {
            "ok": True,
            "file": filename,
            "size": size,
            "timestamp": datetime.utcnow().isoformat() + "Z",
        })

    # ── helpers ──────────────────────────────────────────────

    def _send_json(self, code, data):
        body = __import__("json").dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _log(self, fmt, *args):
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        msg = fmt % args if args else fmt
        print(f"[{ts}] {msg}", flush=True)

    def _parse_multipart(self, content_type):
        """Minimal multipart parser — no external deps."""
        import email.parser

        # Extract boundary
        boundary = None
        for part in content_type.split(";"):
            part = part.strip()
            if part.startswith("boundary="):
                boundary = part.split("=", 1)[1].strip('"')
                break
        if not boundary:
            raise ValueError("No boundary in Content-Type")

        # Read body
        content_length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(content_length)

        # Create MIME message
        msg = email.parser.BytesParser().parsebytes(
            b"Content-Type: multipart/form-data; boundary=" + boundary.encode() + b"\r\n\r\n" + raw
        )

        fields = {}
        for part in msg.walk():
            if part.get_content_maintype() == "multipart":
                continue
            disp = part.get_content_disposition() or ""
            name = None
            for param in disp.split(";"):
                param = param.strip()
                if param.startswith("name="):
                    name = param.split("=", 1)[1].strip('"\'')
                elif param.startswith("filename="):
                    fname = param.split("=", 1)[1].strip('"\'')
                    if fname:
                        name = name or "file"
                        fields["_filename"] = fname
            if name:
                payload = part.get_payload(decode=True)
                if payload is not None:
                    fields[name] = payload
                else:
                    fields[name] = b""
        return fields

    # Suppress default request logging
    def log_message(self, fmt, *args):
        pass


def main():
    global UPLOAD_DIR, AUTH_TOKEN

    parser = argparse.ArgumentParser(description="Write-only file upload webhook for port scan results")
    parser.add_argument("--token", required=True, help="Shared secret auth token (nodes send this in X-Auth-Token header)")
    parser.add_argument("--port", type=int, default=9090, help="Port to listen on (default: 9090)")
    parser.add_argument("--dir", default="/var/scans", help="Directory to save uploaded files (default: /var/scans)")
    parser.add_argument("--bind", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    args = parser.parse_args()

    AUTH_TOKEN = args.token
    UPLOAD_DIR = os.path.abspath(args.dir)
    os.makedirs(UPLOAD_DIR, exist_ok=True)

    server = HTTPServer((args.bind, args.port), WebhookHandler)
    print(f"[+] Webhook receiver running on http://{args.bind}:{args.port}")
    print(f"[+] Saving uploads to: {UPLOAD_DIR}")
    print(f"[+] Auth token: {'*' * len(AUTH_TOKEN)}")
    print(f"[+] Mode: WRITE-ONLY (GET/HEAD are rejected)")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[!] Shutting down.")
        server.shutdown()


if __name__ == "__main__":
    main()
