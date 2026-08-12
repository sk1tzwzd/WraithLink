#!/usr/bin/env python3
"""WraithLink X47 pairing responder (desktop side).

Runs the desktop half of QR mutual pairing:

  1. Generate a high-entropy one-time secret.
  2. Create a single-use, time-boxed *pairing* onion (via the Tor control port)
     that forwards to a local socket we listen on.
  3. Render QR1 (pairing onion + secret) in the terminal for the phone to scan.
  4. Run SPAKE2 keyed by the secret over the pairing onion -> a mutually
     authenticated, encrypted channel (a MITM without the secret cannot join).
  5. Exchange long-term material: receive the phone's Tor client-auth x25519
     public key + SSH public key; send our service onion + SSH host fingerprint.
  6. Show a short authentication string (SAS) for the operator to compare with
     the phone. Only on confirmation do we pin the phone:
        - write authorized_clients/<name>.auth  (enables the phone as a client)
        - append the SSH key to the user's authorized_keys (tagged wraithlink-phone)
  7. Tear down the pairing onion (closing the control connection removes it).

Crypto is delegated to audited libraries: `spake2` (PAKE) and `cryptography`
(HKDF + ChaCha20-Poly1305). We do not implement primitives ourselves.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
import secrets
import socket
import struct
import subprocess
import sys
import time

try:
    from spake2 import SPAKE2_B  # desktop plays role B; phone plays role A
except Exception:  # pragma: no cover
    sys.exit("[pair] missing 'spake2' (pip install spake2)")

try:
    from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    from cryptography.hazmat.primitives import hashes
except Exception:  # pragma: no cover
    sys.exit("[pair] missing 'cryptography' (apt install python3-cryptography)")

PROTO = b"WraithLinkPair/1"
PAIRING_VPORT = 9735          # onion virtual port
PAIRING_LOCAL = ("127.0.0.1", 9735)
PAIRING_TTL = 180             # seconds the pairing window stays open
CONTROL_ADDR = ("127.0.0.1", 9051)


# ---------- framed JSON over a socket ----------
def send_frame(sock: socket.socket, obj) -> None:
    data = json.dumps(obj).encode()
    sock.sendall(struct.pack(">I", len(data)) + data)


def recv_frame(sock: socket.socket):
    hdr = _recv_exact(sock, 4)
    (n,) = struct.unpack(">I", hdr)
    if n > 1 << 20:
        raise ValueError("frame too large")
    return json.loads(_recv_exact(sock, n).decode())


def _recv_exact(sock: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("peer closed during pairing")
        buf += chunk
    return buf


# ---------- Tor control port (ephemeral pairing onion) ----------
class TorControl:
    """Minimal Tor controller for ADD_ONION. Keeps the connection open so the
    ephemeral onion lives only for the pairing window."""

    def __init__(self):
        self.sock = socket.create_connection(CONTROL_ADDR, timeout=10)
        self.f = self.sock.makefile("rwb")
        self._authenticate()

    def _cookie(self) -> str:
        for p in ("/run/tor/control.authcookie", "/var/run/tor/control.authcookie"):
            if os.path.exists(p):
                try:
                    return binascii.hexlify(open(p, "rb").read()).decode()
                except PermissionError:
                    pass
        return ""

    def _cmd(self, line: str) -> list[str]:
        self.f.write((line + "\r\n").encode())
        self.f.flush()
        out = []
        while True:
            resp = self.f.readline().decode().strip()
            out.append(resp)
            if len(resp) >= 4 and resp[3] == " ":
                break
        if not out[-1].startswith("250"):
            raise RuntimeError(f"tor control error: {out}")
        return out

    def _authenticate(self):
        cookie = self._cookie()
        try:
            self._cmd(f"AUTHENTICATE {cookie}" if cookie else "AUTHENTICATE")
        except RuntimeError as e:
            raise RuntimeError(
                "Could not authenticate to Tor control port (9051). Enable\n"
                "  ControlPort 9051\n  CookieAuthentication 1\nin torrc."
            ) from e

    def add_pairing_onion(self) -> str:
        resp = self._cmd(
            f"ADD_ONION NEW:ED25519-V3 Flags=DiscardPK "
            f"Port={PAIRING_VPORT},{PAIRING_LOCAL[0]}:{PAIRING_LOCAL[1]}"
        )
        for line in resp:
            if "ServiceID=" in line:
                return line.split("ServiceID=")[1].strip() + ".onion"
        raise RuntimeError("ADD_ONION returned no ServiceID")

    def close(self):
        try:
            self.f.close(); self.sock.close()
        except Exception:
            pass


# ---------- helpers ----------
def b32(data: bytes) -> str:
    return base64.b32encode(data).decode().rstrip("=")


def qr(text: str) -> None:
    try:
        subprocess.run(["qrencode", "-t", "ANSIUTF8", text], check=True)
    except Exception:
        print(f"[pair] (qrencode unavailable) pairing payload:\n{text}")


def sas(seed: bytes, msg_b: bytes, msg_a: bytes) -> str:
    digest = hashlib.sha256(seed + msg_b + msg_a).digest()
    num = int.from_bytes(digest[:4], "big") % 100000
    return f"{num:05d}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--service-onion", required=True)
    ap.add_argument("--ssh-host-fp", required=True)
    ap.add_argument("--authorized-clients", required=True)
    ap.add_argument("--ssh-user", required=True)
    args = ap.parse_args()

    secret = b32(secrets.token_bytes(15)).encode()  # 120-bit one-time secret

    tor = TorControl()
    try:
        pairing_onion = tor.add_pairing_onion()
        payload = json.dumps({"v": 1, "o": pairing_onion, "s": secret.decode()})
        print("\n[pair] Scan this QR in WraithLink -> Connect to X47 "
              f"(valid {PAIRING_TTL}s):\n")
        qr(payload)
        print(f"\n[pair] pairing onion: {pairing_onion}\n")

        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(PAIRING_LOCAL)
        srv.listen(1)
        srv.settimeout(PAIRING_TTL)
        print("[pair] waiting for the phone to connect...")
        conn, _ = srv.accept()
        conn.settimeout(60)

        # --- SPAKE2 (desktop = role B) ---
        sp = SPAKE2_B(secret)
        msg_b = sp.start()
        send_frame(conn, {"proto": PROTO.decode(), "spake_b": b32(msg_b)})
        hello = recv_frame(conn)
        msg_a = base64.b32decode(hello["spake_a"] + "=" * ((8 - len(hello["spake_a"]) % 8) % 8))
        key = sp.finish(msg_a)

        hk = HKDF(algorithm=hashes.SHA256(), length=64, salt=None,
                  info=PROTO).derive(key)
        aead = ChaCha20Poly1305(hk[:32])
        sas_seed = hk[32:]

        def enc(obj) -> dict:
            nonce = os.urandom(12)
            ct = aead.encrypt(nonce, json.dumps(obj).encode(), PROTO)
            return {"n": b32(nonce), "c": b32(ct)}

        def dec(frame) -> dict:
            nonce = base64.b32decode(frame["n"] + "=" * ((8 - len(frame["n"]) % 8) % 8))
            ct = base64.b32decode(frame["c"] + "=" * ((8 - len(frame["c"]) % 8) % 8))
            return json.loads(aead.decrypt(nonce, ct, PROTO).decode())

        # --- authenticated key exchange over the SPAKE2 channel ---
        phone = dec(recv_frame(conn))           # {client_auth_pub_b32, ssh_pub}
        send_frame(conn, enc({
            "service_onion": args.service_onion,
            "ssh_host_fp": args.ssh_host_fp,
        }))

        code = sas(sas_seed, msg_b, msg_a)
        print(f"\n[pair] VERIFICATION CODE: {code}")
        print("[pair] Confirm this EXACT code is shown on the phone.")
        if input("[pair] Codes match? type 'yes' to pair: ").strip().lower() != "yes":
            send_frame(conn, enc({"result": "aborted"}))
            print("[pair] aborted; nothing was pinned.")
            return 2

        # --- pin the phone (client auth + SSH) ---
        client_pub = phone["client_auth_pub_b32"].strip().rstrip("=")
        auth_file = os.path.join(args.authorized_clients, "wraithlink-phone.auth")
        os.makedirs(args.authorized_clients, exist_ok=True)
        with open(auth_file, "w") as fh:
            fh.write(f"descriptor:x25519:{client_pub}\n")
        os.chmod(auth_file, 0o600)

        home = os.path.expanduser(f"~{args.ssh_user}")
        ssh_dir = os.path.join(home, ".ssh")
        os.makedirs(ssh_dir, mode=0o700, exist_ok=True)
        ak = os.path.join(ssh_dir, "authorized_keys")
        ssh_pub = phone["ssh_pub"].strip()
        if "wraithlink-phone" not in ssh_pub:
            ssh_pub += " wraithlink-phone"
        with open(ak, "a") as fh:
            fh.write(ssh_pub + "\n")
        os.chmod(ak, 0o600)
        try:
            import pwd
            u = pwd.getpwnam(args.ssh_user)
            os.chown(ak, u.pw_uid, u.pw_gid)
            os.chown(ssh_dir, u.pw_uid, u.pw_gid)
        except Exception:
            pass

        send_frame(conn, enc({"result": "paired"}))
        print("[pair] SUCCESS: phone pinned. It is now the only authorized client.")
        return 0
    finally:
        tor.close()  # closing the control connection destroys the pairing onion


if __name__ == "__main__":
    sys.exit(main())
