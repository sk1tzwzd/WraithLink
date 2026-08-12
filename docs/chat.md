# WraithLink (messenger) - threat model & protocol

The flagship secure messenger, shipped as the **WraithLink** app (`net.wraithlink.chat`).
See [WraithLink-Messenger](https://github.com/sk1tzwzd/WraithLink-Messenger) and
`apps/chat/README.md` (stub) for the product overview. This doc records the security rationale.

## Threat model
- **Adversary:** network observers, malicious peers, device seizure.
- **Protected:** message confidentiality/integrity, forward secrecy, post-compromise
  security, network metadata (IP/location) via Tor, no server to subpoena.
- **Not protected:** an adversary with full control of a running, unlocked device; global
  passive adversaries doing long-term Tor traffic correlation; endpoint malware.

## Protocol
1. **Identity:** Curve25519 Signal identity key sealed under a StrongBox-backed AES-GCM
   master key (TEE/software fallback on emulators). Peers verify each other with PGP
   biometric safe-words (`Fingerprints.safeWords`) out-of-band.
2. **Verification gate (OTP / SAS):** before any message can be sent, both peers must
   confirm a matching 6-digit Short Authentication String derived from the two identity
   keys (`VerificationCode`), enforced by `VerificationManager`. A MITM cannot make both
   sides show the same code. Verification state is RAM-only.
3. **Handshake:** X3DH using identity + signed prekey + one-time prekeys (libsignal).
4. **Messaging:** Double Ratchet (libsignal) - new keys per message.
5. **Transport:** Tor v3 onion service per install (embedded tor-android); peers dial via
   the local SOCKS5 proxy. Framed JSON ciphertext over the onion virtual port.
6. **Storage (nothing anywhere):** messages live ONLY in process RAM (`EphemeralStore`).
   Every message auto-disappears on a per-conversation timer; **view-once** messages burn
   on first display; a daemon sweeper purges expired messages proactively. No disk cache,
   no database, no server. `wipeAll()` is the panic/lock/duress clear, and the UI sets
   `FLAG_SECURE` so content can't be screenshotted or recorded.

## Contact exchange
Peers exchange a QR payload containing fingerprint, onion address, public identity key,
and an optional prekey bundle. Scanning begins SAS verification and session establishment.

## X47 desktop link
Optional QR mutual pairing to the owner's X47 Ubuntu desktop over Tor (SPAKE2 + SAS +
ChaCha20-Poly1305), producing Tor client-auth + SSH credentials unique to this phone.

## Why not literally "on the blockchain"
A public ledger makes data permanent and world-readable — incompatible with "no logs".
Messages never touch a chain. `IdentityAnchor` (handle → pubkey binding) exists as a
stub and stays **off / unadvertised in v1** (milestone 2 at earliest).

## Crypto policy
We use **libsignal** and **libsodium** exclusively for primitives, plus platform JCA for
HKDF / ChaCha20-Poly1305. We do not implement ratchets, AEAD, or key exchange by hand.
Any change here requires review against these libraries' documented APIs.

## Shipping
Built from the sibling [WraithLink-Messenger](https://github.com/sk1tzwzd/WraithLink-Messenger)
checkout (`WL_CHAT_SRC` or `../WraithLink-Messenger`) via `apps/chat/build-and-stage.sh`,
signed with a dedicated `wraithlink-chat` keystore (not the platform key), and imported as a
presigned `android_app_import` so it is preinstalled but user-removable. Promoted in the
first-boot wizard and mentioned on the web install screen.
