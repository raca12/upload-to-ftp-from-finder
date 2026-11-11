#!/usr/bin/env python3
"""Test için minik FTP sunucusu (LIST/NLST/STOR/MKD/PASV/EPSV).

Kullanım:
    python3 tools/mock_ftp_server.py [port] [root]

Kullanıcı/şifre kontrolü yok: her USER/PASS kabul edilir.
"""
import os
import socket
import sys
import threading
from datetime import datetime

HOST = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 2121
ROOT = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else
                       os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".mock-ftp"))
os.makedirs(ROOT, exist_ok=True)


def listing_line(path: str) -> str:
    st = os.stat(path)
    mode = "drwxr-xr-x" if os.path.isdir(path) else "-rw-r--r--"
    when = datetime.fromtimestamp(st.st_mtime).strftime("%b %d %H:%M")
    return f"{mode}    1 owner    group    {st.st_size:>8} {when} {os.path.basename(path)}"


class Session(threading.Thread):
    def __init__(self, conn, addr):
        super().__init__(daemon=True)
        self.conn = conn
        self.cwd = "/"
        self.pasv = None
        self.file = conn.makefile("rwb", buffering=0)

    # --- yardımcılar -------------------------------------------------
    def send(self, line: str):
        self.file.write((line + "\r\n").encode())

    def real(self, remote: str) -> str:
        remote = remote.lstrip("/")
        return os.path.join(ROOT, remote) if remote else ROOT

    def open_data(self):
        if not self.pasv:
            return None
        try:
            data, _ = self.pasv.accept()
            return data
        except OSError:
            return None
        finally:
            try:
                self.pasv.close()
            except OSError:
                pass
            self.pasv = None

    # --- komutlar ----------------------------------------------------
    def run(self):
        self.send("220 mock FTP hazır")
        try:
            while True:
                raw = self.file.readline()
                if not raw:
                    break
                line = raw.decode(errors="replace").strip()
                if not line:
                    continue
                cmd, _, arg = line.partition(" ")
                cmd = cmd.upper()
                handler = getattr(self, f"do_{cmd}", None)
                if handler is None:
                    self.send("502 komut desteklenmiyor")
                elif handler(arg) is False:
                    break
        except OSError:
            pass
        finally:
            try:
                self.conn.close()
            except OSError:
                pass

    def do_USER(self, arg):
        self.send("331 şifre gerekli")

    def do_PASS(self, arg):
        self.send("230 giriş tamam")

    def do_SYST(self, arg):
        self.send("215 UNIX Type: L8")

    def do_FEAT(self, arg):
        self.send("211-Features:")
        self.send(" SIZE")
        self.send("211 End")

    def do_OPTS(self, arg):
        self.send("200 ok")

    def do_TYPE(self, arg):
        self.send("200 type ayarlandı")

    def do_PWD(self, arg):
        self.send(f'257 "{self.cwd}"')

    def do_CWD(self, arg):
        target = os.path.normpath(os.path.join(self.cwd, arg)).replace("\\", "/")
        if not target.startswith("/"):
            target = "/" + target
        if os.path.isdir(self.real(target)):
            self.cwd = target
            self.send("250 klasör değişti")
        else:
            self.send("550 klasör yok")

    def do_MKD(self, arg):
        path = self.real(os.path.join(self.cwd, arg))
        try:
            os.makedirs(path, exist_ok=True)
            self.send("257 klasör oluşturuldu")
        except OSError:
            self.send("550 oluşturulamadı")

    def do_SIZE(self, arg):
        path = self.real(os.path.join(self.cwd, arg))
        if os.path.isfile(path):
            self.send(f"213 {os.path.getsize(path)}")
        else:
            self.send("550 dosya yok")

    def do_PASV(self, arg):
        self.pasv = socket.socket()
        self.pasv.bind((HOST, 0))
        self.pasv.listen(1)
        port = self.pasv.getsockname()[1]
        self.send(f"227 Entering Passive Mode ({HOST.replace('.', ',')},{port >> 8},{port & 0xFF})")

    def do_EPSV(self, arg):
        self.pasv = socket.socket()
        self.pasv.bind((HOST, 0))
        self.pasv.listen(1)
        self.send(f"229 Entering Extended Passive Mode (|||{self.pasv.getsockname()[1]}|)")

    def do_LIST(self, arg):
        target = self.real(os.path.join(self.cwd, arg)) if arg and not arg.startswith("-") else self.real(self.cwd)
        if not os.path.isdir(target):
            self.send("550 klasör yok")
            return
        self.send("150 liste geliyor")
        data = self.open_data()
        if data:
            payload = "\r\n".join(listing_line(os.path.join(target, name))
                                  for name in sorted(os.listdir(target))) + "\r\n"
            data.sendall(payload.encode())
            data.close()
        self.send("226 liste tamam")

    def do_NLST(self, arg):
        target = self.real(self.cwd)
        self.send("150 liste geliyor")
        data = self.open_data()
        if data:
            payload = "\r\n".join(sorted(os.listdir(target))) + "\r\n"
            data.sendall(payload.encode())
            data.close()
        self.send("226 liste tamam")

    def do_STOR(self, arg):
        path = self.real(os.path.join(self.cwd, arg))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.send("150 yüklemeye hazır")
        data = self.open_data()
        if data:
            with open(path, "wb") as fh:
                while True:
                    chunk = data.recv(65536)
                    if not chunk:
                        break
                    fh.write(chunk)
            data.close()
        self.send("226 yükleme tamam")

    def do_DELE(self, arg):
        path = self.real(os.path.join(self.cwd, arg))
        try:
            os.remove(path)
            self.send("250 silindi")
        except OSError:
            self.send("550 silinemedi")

    def do_QUIT(self, arg):
        self.send("221 görüşürüz")
        return False


def main():
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(8)
    print(f"mock FTP: ftp://{HOST}:{PORT}  (kök: {ROOT})", flush=True)
    # örnek klasörler
    for d in ("resimler", "resimler/2026", "arsiv"):
        os.makedirs(os.path.join(ROOT, d), exist_ok=True)
    while True:
        conn, addr = server.accept()
        Session(conn, addr).start()


if __name__ == "__main__":
    main()
