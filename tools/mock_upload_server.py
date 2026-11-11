#!/usr/bin/env python3
"""Yerel test sunucusu: multipart POST /upload kabul eder, dosya linki döndürür.

Kullanım:
    python3 tools/mock_upload_server.py [port]
"""
import json
import os
import sys
from email.parser import BytesParser
from email.policy import default as email_policy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FILES = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".mock-upload"))
os.makedirs(FILES, exist_ok=True)


def parse_multipart(body: bytes, content_type: str):
    """Basit multipart/form-data ayrıştırıcı: {name: (filename, bytes)}"""
    message = BytesParser(policy=email_policy).parsebytes(
        b"Content-Type: " + content_type.encode() + b"\r\nMIME-Version: 1.0\r\n\r\n" + body
    )
    parts = {}
    if not message.is_multipart():
        return parts
    for part in message.iter_parts():
        field = part.get_param("name", header="content-disposition")
        if not field:
            continue
        filename = part.get_param("filename", header="content-disposition")
        parts[field] = (filename, part.get_payload(decode=True) or b"")
    return parts


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[mock] " + fmt % args + "\n")

    def _send(self, code, payload: bytes, content_type="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        if self.path != "/upload":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        parts = parse_multipart(body, self.headers.get("Content-Type", ""))
        if "file" not in parts or not parts["file"][0]:
            self._send(400, json.dumps({"ok": False, "error": "file alanı yok"}).encode())
            return
        filename = os.path.basename(parts["file"][0])
        data = parts["file"][1]
        with open(os.path.join(FILES, filename), "wb") as fh:
            fh.write(data)
        base = f"http://127.0.0.1:{self.server.server_port}"
        folder = parts.get("klasor", ("", b""))[1].decode(errors="replace")
        payload = json.dumps(
            {"ok": True, "url": f"{base}/files/{filename}", "thumb": "", "klasor": folder, "boyut": len(data)},
            ensure_ascii=False,
        ).encode()
        self._send(200, payload)

    def do_GET(self):
        if not self.path.startswith("/files/"):
            self.send_error(404)
            return
        path = os.path.join(FILES, os.path.basename(self.path[len("/files/"):]))
        if not os.path.isfile(path):
            self.send_error(404)
            return
        with open(path, "rb") as fh:
            self._send(200, fh.read(), "application/octet-stream")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    print(f"mock upload server: http://127.0.0.1:{port}  (dosyalar: {FILES})", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
