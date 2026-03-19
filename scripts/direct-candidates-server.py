#!/usr/bin/env python3
import json
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8096
EXCLUDED_PREFIXES = ("127.", "172.19.")
EXCLUDED_INTERFACES = ("lo", "tun", "et_", "dummy")


def get_ipv4_candidates():
    try:
        output = subprocess.check_output(
            ["ip", "-4", "-j", "addr", "show", "scope", "global"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return []

    try:
        data = json.loads(output)
    except json.JSONDecodeError:
        return []

    candidates = []
    seen = set()

    for iface in data:
        ifname = iface.get("ifname", "")
        if ifname.startswith(EXCLUDED_INTERFACES):
            continue

        for addr_info in iface.get("addr_info", []):
            if addr_info.get("family") != "inet":
                continue
            local = addr_info.get("local", "")
            if not local or local.startswith(EXCLUDED_PREFIXES):
                continue
            if local in seen:
                continue
            seen.add(local)
            candidates.append(
                {
                    "ifname": ifname,
                    "ip": local,
                    "origin": f"http://{local}:8080",
                }
            )

    return candidates


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/":
            self.send_response(404)
            self.end_headers()
            return

        payload = {
            "candidates": get_ipv4_candidates(),
        }
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()
