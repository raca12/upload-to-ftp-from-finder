#!/usr/bin/env python3
"""Test için minik SFTP sunucusu (paramiko).

Kullanım:
    python3 tools/mock_sftp_server.py [port] [root]

Her kullanıcı/parola kabul edilir. Gereksinim: pip install paramiko
"""
import os
import socket
import sys
import threading

import paramiko

paramiko.util.log_to_file('/tmp/paramiko.log')

HOST = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 2222
ROOT = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else
                       os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".mock-sftp"))
os.makedirs(ROOT, exist_ok=True)


class Handle(paramiko.SFTPHandle):
    def stat(self):
        try:
            return paramiko.SFTPAttributes.from_stat(os.fstat(self.readfile.fileno()))
        except OSError as exc:
            return paramiko.SFTPServer.convert_errno(exc.errno)


class Server(paramiko.SFTPServerInterface):
    def _real(self, path):
        return os.path.join(ROOT, path.lstrip("/"))

    def list_folder(self, path):
        real = self._real(path)
        try:
            out = []
            for name in os.listdir(real):
                attr = paramiko.SFTPAttributes.from_stat(os.stat(os.path.join(real, name)))
                attr.filename = name
                out.append(attr)
            return out
        except OSError as exc:
            return paramiko.SFTPServer.convert_errno(exc.errno)

    def stat(self, path):
        try:
            return paramiko.SFTPAttributes.from_stat(os.stat(self._real(path)))
        except OSError as exc:
            return paramiko.SFTPServer.convert_errno(exc.errno)

    def lstat(self, path):
        return self.stat(path)

    def open(self, path, flags, attr):
        real = self._real(path)
        try:
            binary_flag = getattr(os, "O_BINARY", 0)
            flags |= binary_flag
            mode = getattr(attr, "st_mode", None) or 0o666
            fd = os.open(real, flags, mode)
        except OSError as exc:
            return paramiko.SFTPServer.convert_errno(exc.errno)
        if flags & (os.O_WRONLY | os.O_RDWR):
            handle = Handle(flags)
            handle.writefile = os.fdopen(fd, "wb")
        else:
            handle = Handle(flags)
            handle.readfile = os.fdopen(fd, "rb")
        os.makedirs(os.path.dirname(real), exist_ok=True)
        return handle

    def remove(self, path):
        try:
            os.remove(self._real(path))
            return paramiko.SFTP_OK
        except OSError as exc:
            return paramiko.SFTPServer.convert_errno(exc.errno)

    def rename(self, oldpath, newpath):
        try:
            os.rename(self._real(oldpath), self._real(newpath))
            return paramiko.SFTP_OK
        except OSError as exc:
            return paramiko.SFTPServer.convert_errno(exc.errno)

    def mkdir(self, path, attr):
        try:
            os.makedirs(self._real(path), exist_ok=True)
            return paramiko.SFTP_OK
        except OSError as exc:
            return paramiko.SFTPServer.convert_errno(exc.errno)

    def rmdir(self, path):
        try:
            os.rmdir(self._real(path))
            return paramiko.SFTP_OK
        except OSError as exc:
            return paramiko.SFTPServer.convert_errno(exc.errno)

    def chattr(self, path, attr):
        return paramiko.SFTP_OK


class Interface(paramiko.ServerInterface):
    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL

    def check_auth_publickey(self, username, key):
        return paramiko.AUTH_SUCCESSFUL

    def get_allowed_auths(self, username):
        return "password,publickey"

    def check_channel_request(self, kind, chanid):
        if kind == "session":
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED


def handle_connection(client, host_key):
    transport = paramiko.Transport(client)
    transport.add_server_key(host_key)
    transport.set_subsystem_handler("sftp", paramiko.SFTPServer, Server)
    try:
        transport.start_server(server=Interface())
    except Exception as exc:
        print("server error:", exc, flush=True)
        return
    # Kanalı kapatmıyoruz ve referansı tutuyoruz; sftp alt sistemi kendi
    # iş parçacığında çalışıyor. Referans düşerse kanal GC ile kapanır.
    channels = []
    while transport.is_active():
        try:
            channel = transport.accept(1)
            if channel is not None:
                channels.append(channel)
        except Exception:
            break


KEY_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".mock-sftp-key")
if not os.path.exists(KEY_PATH):
    paramiko.RSAKey.generate(2048).write_private_key_file(KEY_PATH)


def main():
    host_key = paramiko.RSAKey(filename=KEY_PATH)
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(8)
    print(f"mock SFTP: sftp://{HOST}:{PORT}  (kök: {ROOT})", flush=True)
    for folder in ("uploads", "uploads/2026", "images"):
        os.makedirs(os.path.join(ROOT, folder), exist_ok=True)
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle_connection, args=(client, host_key), daemon=True).start()


if __name__ == "__main__":
    main()
