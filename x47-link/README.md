# WraithLink to X47 remote link

Connect a WraithLink phone to your x86_64 [X47 Ubuntu](https://github.com/sk1tzwzd/ubuntu-x47-build)
desktop, "like a phone connects to Kali" - but pointed at your real machine rather than
an on-phone chroot. X47 stays x86_64; the phone is a secure thin client.

## Two parts

1. **On-device Linux (offline):** WraithLink rebrands GrapheneOS's Terminal/AVF VM so you
   also have a lightweight ARM64 Linux shell on the phone with no network needed. (Handled
   in the OS build; see `docs/on-device-linux.md`.)
2. **Remote to full X47 (this folder):** Tor onion + client auth, then SSH + VNC/RDP to your desktop.

## Exclusive linking (Tor onion + client auth + QR pairing)

The link uses a **Tor v3 onion service with client authorization**, so knowing the
`.onion` address is useless to anyone who is not the paired phone. SSH is key-only and
VNC is loopback-only, reachable only through the client-authed onion. **Nothing is
shipped preconfigured** - the onion and every key are generated locally, and the phone
learns them only during pairing. See [`docs/x47-pairing.md`](../docs/x47-pairing.md) for
the full protocol and threat model.

## Setup

**On X47:** copy both helper files into your X47 repo, then set up and pair:

```bash
cd ~/Ubuntu\ 26\ Custom\ Build/ubuntu-x47-build
cp /path/to/WraithLink/x47-link/x47-side/90-wraithlink-remote.sh modules/
cp /path/to/WraithLink/x47-link/x47-side/wraithlink-pair-responder.py modules/
sudo bash modules/90-wraithlink-remote.sh          # first run: service onion, UNPAIRED
sudo bash modules/90-wraithlink-remote.sh pair      # shows QR + verification code
```

**On the phone:** open **Connect to X47** (onboarding or the WraithLink Chat app), scan
the QR shown on the desktop, then confirm the **5-digit verification code matches on both
screens**. That pins this phone as the only authorized client.

Manage the link on X47:

```bash
sudo bash modules/90-wraithlink-remote.sh status    # paired / unpaired
sudo bash modules/90-wraithlink-remote.sh revoke    # unpair (block the phone)
```

The helper installs/hardens `sshd`, creates the client-authed onion, and starts a VNC
server (`wayvnc` on Wayland, else `x11vnc`) bound to loopback.

## WiFi cracking / wireless auditing (runs on X47, not the phone)

The Pixel's internal WiFi chip cannot do monitor mode or packet injection, and enabling
that on-phone would require unlocking the bootloader + root + a NetHunter-style kernel -
which destroys WraithLink's verified boot, attestation, and duress guarantees. So the
phone stays hardened and the wireless work happens on X47 with a proper USB adapter,
driven remotely from the phone over the link above.

**On X47:** plug in a supported USB adapter (Alfa AWUS036ACM / MT7612U recommended) and run:

```bash
cp x47-link/x47-side/91-wireless-audit.sh ~/Ubuntu\ 26\ Custom\ Build/ubuntu-x47-build/modules/
sudo bash modules/91-wireless-audit.sh
```

This installs aircrack-ng, wifite, hcxdumptool/hcxtools, reaver, bettercap, kismet, etc.
**From the phone:** SSH into X47 (ConnectBot) or open the desktop (bVNC) and run the tools
there. Offline hash cracking (hashcat) is much faster with a GPU box.

