# WraithLink to X47 - exclusive pairing

Goal: person A's phone can only ever reach person A's desktop, and no one else's phone
can reach it - even though WraithLink and the X47 helper are downloaded by many people.

## What enforces exclusivity

1. **Tor v3 onion + client authorization.** The desktop's service onion
   (`/var/lib/tor/wraithlink`) only accepts a client holding the matching x25519 private
   key. Anyone who merely learns the `.onion` cannot resolve or connect.
2. **Pinned SSH both ways.** The desktop `authorized_keys` holds exactly the phone's SSH
   public key; the phone pins the desktop's SSH host-key fingerprint captured at pairing.
3. **No shipped secrets.** The WraithLink image and the X47 script contain no onion
   address and no keys. Everything is generated per-device; the phone learns the desktop's
   identity only during pairing. (This is the single most important rule for a
   mass-distributed build.)

## Pairing protocol (implemented)

Desktop responder: [`x47-link/x47-side/wraithlink-pair-responder.py`](../x47-link/x47-side/wraithlink-pair-responder.py).
Phone side: in [WraithLink-Messenger](https://github.com/sk1tzwzd/WraithLink-Messenger)
under `app/src/main/java/net/wraithlink/link/`
(`X47LinkPairing`, `PairingCrypto`, `X47Credentials`, `X47LinkActivity`).

```mermaid
sequenceDiagram
  participant D as X47 Desktop
  participant P as WraithLink Phone
  D->>D: create single-use pairing onion + one-time secret
  D-->>P: QR1 = {pairing onion, secret}
  P->>D: connect pairing onion via Tor; SPAKE2 (P=role A, D=role B)
  Note over P,D: HKDF-SHA256(info="WraithLinkPair/1") -> AEAD key + SAS seed
  P->>D: seal{ client_auth_pubkey (x25519 b32), ssh_pub }
  D->>P: seal{ service_onion, ssh_host_fp }
  Note over P,D: SAS = 5 digits of SHA256(sas_seed||spake_b||spake_a)
  Note over P,D: user confirms SAS matches on BOTH screens
  D->>D: write authorized_clients/wraithlink-phone.auth + authorized_keys
  D->>D: destroy pairing onion
  P->>P: store service onion + pinned host fp; keep keys in Keystore
```

- **PAKE:** SPAKE2 keyed by the one-time secret. A MITM without the secret cannot derive
  the channel key, so the exchanged keys are authenticated. Crypto is delegated to
  audited libraries (Python `spake2` + `cryptography`; on Android, Tink for HKDF/AEAD and
  a SPAKE2 implementation byte-compatible with `spake2`). We do not invent primitives.
- **SAS:** a short belt-and-suspenders check that also confirms the operator scanned the
  correct QR. Mismatch aborts pairing and pins nothing.
- **Time-boxed / single-use:** the pairing onion lives ~180s and is destroyed afterward.

## Connecting after pairing

The phone installs its stored x25519 client-auth key into the embedded Tor
`ClientOnionAuthDir`, then launches ConnectBot (SSH, host-key pinned) or bVNC via the Tor
SOCKS proxy (`127.0.0.1:9050`). Without the stored private keys nothing resolves, so only
this phone can link. See `X47Connect` in the Messenger repo (`net.wraithlink.link`).

## Re-pairing and revocation

- **Revoke a phone (desktop):** `sudo bash modules/90-wraithlink-remote.sh revoke` removes
  the client-auth entry and the SSH key. The onion instantly stops accepting that phone.
- **Re-pair:** run `pair` again; a new pairing onion + secret are generated.

## Release / QA security checklist

- [ ] No key, onion address, or secret is present in any shipped image or script.
- [ ] An unpaired client cannot resolve the service onion (client auth enforced).
- [ ] SAS mismatch aborts pairing; the pairing onion is single-use and expires.
- [ ] `revoke` removes `authorized_clients/*.auth` + the SSH key and blocks the phone.
- [ ] SSH host-key pin mismatch on the phone aborts the connection.
- [ ] The service onion binds SSH/VNC to loopback only (never a public interface).
