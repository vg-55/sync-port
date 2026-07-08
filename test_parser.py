#!/usr/bin/env python3
"""Quick test to debug multipart parsing."""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, os, sys
from datetime import datetime

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        ct = self.headers.get("Content-Type","")
        cl = int(self.headers.get("Content-Length",0))
        raw = self.rfile.read(cl)
        
        # Parse boundary
        boundary = None
        for p in ct.split(";"):
            p = p.strip()
            if p.startswith("boundary="):
                boundary = p.split("=",1)[1].strip('"')
        print(f"CT={ct}", flush=True)
        print(f"CL={cl}", flush=True)
        print(f"Boundary={boundary}", flush=True)
        print(f"Body len={len(raw)}", flush=True)
        print(f"Body repr first 600={repr(raw[:600])}", flush=True)
        
        # Try parsing
        if boundary:
            delim = ("--" + boundary).encode()
            parts = raw.split(delim)
            print(f"Parts after split={len(parts)}", flush=True)
            for i, part in enumerate(parts):
                print(f"  Part[{i}] len={len(part)} repr first 200={repr(part[:200])}", flush=True)
        
        self.send_response(200)
        self.end_headers()

if __name__ == "__main__":
    s = HTTPServer(("0.0.0.0", 9999), H)
    print("[+] Debug server on :9999", flush=True)
    s.serve_forever()
