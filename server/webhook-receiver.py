#!/usr/bin/env python3
"""
webhook-receiver.py -- Write-only file upload webhook for the MAIN VPS.

Receives port scan files from scanning nodes via HTTP POST.
- Streams directly to disk -- handles multi-GB files on tiny VPS.
- Write-only: GET/HEAD/anything-else rejected.

Start:
    python3 webhook-receiver.py --token mysecrettoken --port 9090 --dir /var/scans
"""

import argparse
import os
import sys
import tempfile
import hmac
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler


UPLOAD_DIR = None
AUTH_TOKEN = None


class WebhookHandler(BaseHTTPRequestHandler):
    """Write-only handler: accepts POST /upload, rejects everything else."""

    def do_GET(self):
        self._send_json(405, {"error": "GET not allowed. Write-only endpoint."})

    def do_HEAD(self):
        self._send_json(405, {"error": "HEAD not allowed."})

    def do_POST(self):
        if self.path != "/upload":
            self._send_json(404, {"error": "Not found. Only /upload is available."})
            return

        # ---- Auth check ----
        token = self.headers.get("X-Auth-Token", "")
        if not hmac.compare_digest(token, AUTH_TOKEN):
            self._send_json(403, {"error": "Invalid or missing auth token."})
            self._log("AUTH FAILED from %s", self.client_address[0])
            return

        content_type = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in content_type:
            self._send_json(400, {"error": "Expected multipart/form-data."})
            return

        boundary = None
        for part in content_type.split(";"):
            part = part.strip()
            if part.startswith("boundary="):
                boundary = part.split("=", 1)[1].strip('"')
                break
        if not boundary:
            self._send_json(400, {"error": "No boundary in Content-Type."})
            return

        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            self._send_json(400, {"error": "Empty body."})
            return

        # ==== STEP 1: Stream raw body to temp file on disk (NOT in RAM) ====
        tmp_path = None
        try:
            tmp = tempfile.NamedTemporaryFile(
                dir=UPLOAD_DIR, delete=False, suffix=".tmp"
            )
            tmp_path = tmp.name
            remaining = content_length
            while remaining > 0:
                chunk_size = min(65536, remaining)  # 64KB chunks
                chunk = self.rfile.read(chunk_size)
                if not chunk:
                    break
                tmp.write(chunk)
                remaining -= len(chunk)
            tmp.flush()
            tmp.close()
        except Exception as e:
            self._send_json(500, {"error": f"Failed to receive body: {e}"})
            if tmp_path:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
            return

        # ==== STEP 2: Parse the temp file to find filename + file offsets ====
        try:
            filename, file_start, file_end = self._parse_multipart_file(
                tmp_path, boundary
            )
        except Exception as e:
            self._send_json(400, {"error": f"Parse error: {e}"})
            if tmp_path:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
            return

        if not filename:
            self._send_json(400, {"error": "Missing 'file' field."})
            if tmp_path:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
            return

        safe_name = os.path.basename(filename)
        if not safe_name or safe_name in (".", ".."):
            safe_name = "uploaded.txt"

        # ==== STEP 3: Copy file data (at offsets) to final destination ====
        dest = os.path.join(UPLOAD_DIR, safe_name)
        try:
            file_size = file_end - file_start
            with open(tmp_path, "rb") as src, open(dest, "wb") as dst:
                src.seek(file_start)
                copied = 0
                while copied < file_size:
                    chunk = src.read(min(65536, file_size - copied))
                    if not chunk:
                        break
                    dst.write(chunk)
                    copied += len(chunk)
        except OSError as e:
            self._send_json(500, {"error": f"Failed to write file: {e}"})
            if tmp_path:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
            return

        # ==== Cleanup temp ====
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

        self._log(
            "RECEIVED %s (%d bytes) from %s",
            safe_name, file_size, self.client_address[0],
        )
        self._send_json(200, {
            "ok": True,
            "file": safe_name,
            "size": file_size,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

    # ============================================================
    # Multipart parser (disk-based -- no large RAM allocations)
    # ============================================================

    def _parse_multipart_file(self, path, boundary):
        """
        Parse a multipart/form-data file stored on disk.

        Returns (remote_filename, file_start_offset, file_end_offset).

        Walks through multipart sections:
          - "name"  form field  -> captures the desired remote filename
          - "file"  file part   -> records its start/end byte offsets

        Reads only small header regions into RAM; the actual file body
        stays on disk and is referenced by byte offsets.
        """
        delim = ("--" + boundary).encode()       # e.g. b'--boundary123'
        delim_end = ("--" + boundary + "--").encode()
        file_sz = os.path.getsize(path)
        remote_name = None

        with open(path, "rb") as f:

            # Scan forward from byte 0 looking for the first boundary.
            # We read a 256KB window at the start (headers + first boundary
            # are always small).  If the file is shorter than that we read
            # the whole thing.
            buf = f.read(min(256 * 1024, file_sz))
            first = buf.find(delim)
            if first == -1:
                raise ValueError("Boundary not found in body")

            pos = first + len(delim)          # byte just after first boundary
            # skip CRLF / LF after boundary
            if pos + 2 <= file_sz:
                f.seek(pos)
                c2 = f.read(2)
                if c2 == b"\r\n":
                    pos += 2
                elif c2[:1] == b"\n":
                    pos += 1

            while pos < file_sz:
                # ---- read part headers (always small) ----
                f.seek(pos)
                hdr_buf = f.read(8192)
                hdr_end = hdr_buf.find(b"\r\n\r\n")
                if hdr_end == -1:
                    break               # malformed, give up
                headers_raw = hdr_buf[:hdr_end].decode("utf-8", errors="replace")
                body_pos = pos + hdr_end + 4   # first byte of part body

                # parse Content-Disposition
                is_file = False
                field_name = None
                filename = None
                for hline in headers_raw.split("\r\n"):
                    lo = hline.lower()
                    if lo.startswith("content-disposition:"):
                        disp = hline.split(":", 1)[1] if ":" in hline else hline
                        for par in disp.split(";"):
                            p = par.strip()
                            if p.startswith("name="):
                                field_name = p.split("=", 1)[1].strip('"\'')
                            elif p.startswith("filename="):
                                fn = p.split("=", 1)[1].strip('"\'')
                                if fn:
                                    is_file = True
                                    filename = fn

                if not field_name:
                    break

                # ---- find where this part ends (next boundary) ----
                f.seek(body_pos)
                tail = f.read()          # rest of file from body_pos onward
                nb = tail.find(delim)
                if nb == -1:
                    # reached end -- check for closing delimiter
                    if delim_end in tail:
                        part_end = body_pos + tail.find(delim_end)
                    else:
                        part_end = body_pos + len(tail)
                else:
                    part_end = body_pos + nb
                    # strip trailing CRLF before boundary
                    if part_end >= 2:
                        f.seek(part_end - 2)
                        chk = f.read(2)
                        if chk == b"\r\n":
                            part_end -= 2
                        elif chk[1:2] == b"\n":
                            part_end -= 1

                # ---- act on the part ----
                if is_file:
                    return (filename or field_name, body_pos, part_end)

                if field_name == "name" and not is_file:
                    f.seek(body_pos)
                    remote_name = (
                        f.read(part_end - body_pos)
                        .decode("utf-8", errors="replace")
                        .strip()
                    )

                # advance to after this boundary (or stop)
                if nb == -1:
                    break
                pos = part_end
                f.seek(pos)
                check = f.read(len(delim_end))
                if check.startswith(delim_end):
                    break
                # skip CRLF after the boundary line
                f.seek(pos)
                after = f.read(4)
                if after.startswith(b"\r\n"):
                    pos += 2
                elif after.startswith(b"\n"):
                    pos += 1

        return (remote_name, 0, 0)

    # ---- helpers ----

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

    def log_message(self, fmt, *args):
        pass


def main():
    global UPLOAD_DIR, AUTH_TOKEN

    p = argparse.ArgumentParser(description="Write-only file upload webhook")
    p.add_argument("--token", required=True, help="Shared secret auth token")
    p.add_argument("--port", type=int, default=9090, help="Listen port")
    p.add_argument("--dir", default="/var/scans", help="Upload directory")
    p.add_argument("--bind", default="0.0.0.0", help="Bind address")
    args = p.parse_args()

    AUTH_TOKEN = args.token
    UPLOAD_DIR = os.path.abspath(args.dir)
    os.makedirs(UPLOAD_DIR, exist_ok=True)

    srv = HTTPServer((args.bind, args.port), WebhookHandler)
    print(f"[+] Webhook running on http://{args.bind}:{args.port}")
    print(f"[+] Saving to: {UPLOAD_DIR}")
    print(f"[+] Token: {'*' * len(AUTH_TOKEN)}")
    print(f"[+] Mode: WRITE-ONLY")
    print()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n[!] Shutting down.")
        srv.shutdown()


if __name__ == "__main__":
    main()
