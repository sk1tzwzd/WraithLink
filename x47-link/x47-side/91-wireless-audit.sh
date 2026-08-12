#!/usr/bin/env bash
# WraithLink wireless-audit toolkit for X47 Ubuntu.
#
# Drop into ubuntu-x47-build/modules/ as 91-wireless-audit.sh. Installs the WiFi
# cracking / wireless auditing toolchain and helps put an EXTERNAL USB adapter into
# monitor mode. The WraithLink phone drives this remotely over the X47 link (SSH),
# keeping the phone itself fully hardened (no root/unlock, no injection on the Pixel).
#
# You plug the adapter into the X47 machine (server or desktop), NOT the phone.
# Recommended adapters (mainline Linux drivers, reliable monitor mode + injection):
#   * Alfa AWUS036ACM  (MediaTek MT7612U, dual-band)   <- best default
#   * Alfa AWUS036ACHM (MediaTek MT7610U, dual-band)
#   * TP-Link TL-WN722N v1 only (Atheros AR9271, 2.4GHz)
set -euo pipefail

need_root() { [ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }; }
need_root

echo "[wireless-audit] installing toolchain"
apt-get update
apt-get install -y \
  aircrack-ng wifite reaver bully pixiewps \
  hcxtools hcxdumptool \
  mdk4 bettercap kismet \
  hostapd-wpe iw rfkill macchanger

# Driver packages for common external adapters (best-effort; MT76xx is mainline).
apt-get install -y firmware-misc-nonfree 2>/dev/null || true
if command -v dkms >/dev/null 2>&1; then
  apt-get install -y realtek-rtl88xxau-dkms 2>/dev/null || true  # for RTL8812AU adapters
fi

cat <<'USAGE'

[wireless-audit] installed. Typical workflow (run ON X47, driven from the phone via SSH):

  1. Identify the external adapter:
       iw dev            # find e.g. wlan1
       airmon-ng         # list PHYs

  2. Kill interfering processes and start monitor mode:
       sudo airmon-ng check kill
       sudo airmon-ng start wlan1        # creates wlan1mon

  3. Audit (examples):
       sudo wifite --kill                # guided attacks (handshake/PMKID/WPS)
       sudo hcxdumptool -i wlan1mon -o dump.pcapng   # capture PMKID/handshakes
       sudo airodump-ng wlan1mon         # survey
       hcxpcapngtool -o hash.hc22000 dump.pcapng     # convert for hashcat
       hashcat -m 22000 hash.hc22000 wordlist.txt    # crack offline (GPU helps)

  4. Stop and restore:
       sudo airmon-ng stop wlan1mon
       sudo systemctl restart NetworkManager

Notes:
  * Only test networks you are authorised to test.
  * The Pixel's internal WiFi cannot do this; that's why the adapter lives on X47.
  * Offline cracking (hashcat) benefits from a GPU - a Hetzner GEX/GPU box or your
    own desktop with a discrete GPU will be far faster than CPU-only.
USAGE

echo "[wireless-audit] done."
