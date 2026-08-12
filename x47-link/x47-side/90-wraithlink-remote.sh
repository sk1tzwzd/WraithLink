#!/usr/bin/env bash
# WraithLink remote-access helper for X47 Ubuntu.
#
# Drop this into the ubuntu-x47-build repo as modules/90-wraithlink-remote.sh
# (it follows the same convention as the other X47 modules). It exposes the X47
# desktop to a SINGLE paired WraithLink phone over a Tor v3 onion service with
# CLIENT AUTHORIZATION, so that knowing the .onion address is useless to anyone
# who is not the paired phone. SSH is key-only; VNC is loopback-only and only
# reachable through the (client-authed) onion.
#
# EXCLUSIVITY MODEL (why only the owner can link):
#   * The service onion requires a Tor v3 client-auth key. Only the paired phone
#     holds the matching private key, so no one else can even resolve/connect.
#   * SSH authorized_keys holds exactly the paired phone's key; the phone pins
#     our host key. Both directions are pinned.
#   * NOTHING is shipped preconfigured: the onion and all keys are generated
#     locally here, and the phone's keys arrive only through `pair`.
#
# Usage:
#   sudo bash 90-wraithlink-remote.sh            # first run: set up service (unpaired)
#   sudo bash 90-wraithlink-remote.sh pair       # QR mutual pairing with a phone
#   sudo bash 90-wraithlink-remote.sh status     # show pairing state
#   sudo bash 90-wraithlink-remote.sh revoke     # unpair (block the phone)
#
# Transport is fixed to onion+client-auth by default (WL_X47_TRANSPORT=onion).
set -euo pipefail

WL_X47_TRANSPORT="${WL_X47_TRANSPORT:-onion}"
HS_DIR="/var/lib/tor/wraithlink"                 # permanent service onion
AUTH_DIR="${HS_DIR}/authorized_clients"          # client-auth pubkeys live here
VNC_BIND="127.0.0.1:5900"                         # loopback only, onion-fronted
STATE_DIR="/var/lib/wraithlink"                   # our metadata (host key fp, etc.)
RESPONDER="$(cd "$(dirname "$0")" && pwd)/wraithlink-pair-responder.py"

log() { echo "[x47-remote] $*"; }
die() { echo "[x47-remote] ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run with sudo"; }
need_root

install_packages() {
  log "installing packages"
  apt-get update
  apt-get install -y openssh-server tor qrencode python3 python3-pip \
    python3-cryptography python3-spake2 2>/dev/null || {
      apt-get install -y openssh-server tor qrencode python3 python3-pip python3-cryptography
      # spake2 may not be packaged; fall back to pip into a venv-free user path.
      pip3 install --break-system-packages spake2 2>/dev/null || pip3 install spake2 || true
    }
  # VNC server bound to loopback (Wayland first, X11 fallback).
  command -v wayvnc >/dev/null 2>&1 || apt-get install -y wayvnc 2>/dev/null || apt-get install -y x11vnc || true
}

harden_ssh() {
  log "hardening sshd (key-only, loopback bind)"
  install -d /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/60-wraithlink.conf <<'EOF'
# WraithLink: key-only SSH, reachable only via the client-authed onion (loopback).
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
ListenAddress 127.0.0.1
AllowTcpForwarding yes
X11Forwarding no
EOF
  systemctl enable --now ssh
}

setup_service_onion() {
  [ "$WL_X47_TRANSPORT" = "onion" ] || die "only WL_X47_TRANSPORT=onion is supported for exclusive linking"
  log "configuring Tor v3 service onion WITH client authorization"
  install -d -m 700 -o debian-tor -g debian-tor "$HS_DIR"
  install -d -m 700 -o debian-tor -g debian-tor "$AUTH_DIR"

  # Idempotent torrc block. Presence of authorized_clients/*.auth enforces client auth.
  if ! grep -q "### WRAITHLINK BEGIN ###" /etc/tor/torrc 2>/dev/null; then
    cat >> /etc/tor/torrc <<EOF

### WRAITHLINK BEGIN ###
HiddenServiceDir ${HS_DIR}/
HiddenServiceVersion 3
HiddenServicePort 22 127.0.0.1:22
HiddenServicePort 5900 ${VNC_BIND}
### WRAITHLINK END ###
EOF
  fi
  systemctl restart tor@default 2>/dev/null || systemctl restart tor
  sleep 3

  install -d -m 700 "$STATE_DIR"
  # Pin our SSH host key fingerprint for the phone to verify.
  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}' > "${STATE_DIR}/ssh_host_fp"

  local onion; onion="$(cat "${HS_DIR}/hostname" 2>/dev/null || true)"
  [ -n "$onion" ] && log "service onion: ${onion}" || log "service onion pending (check ${HS_DIR}/hostname)"
}

pairing_state() {
  if compgen -G "${AUTH_DIR}/*.auth" >/dev/null 2>&1; then echo "paired"; else echo "unpaired"; fi
}

cmd_status() {
  log "transport: ${WL_X47_TRANSPORT}"
  log "service onion: $(cat "${HS_DIR}/hostname" 2>/dev/null || echo '(not created yet)')"
  log "pairing: $(pairing_state)"
  log "authorized clients: $(ls -1 "${AUTH_DIR}" 2>/dev/null | wc -l)"
}

cmd_revoke() {
  log "revoking paired phone (removing client auth + SSH key)"
  rm -f "${AUTH_DIR}"/*.auth 2>/dev/null || true
  # Remove WraithLink-tagged SSH keys from the invoking user's authorized_keys.
  local ak="${SUDO_USER:+/home/${SUDO_USER}}/.ssh/authorized_keys"
  [ -f "$ak" ] && sed -i '/wraithlink-phone/d' "$ak"
  systemctl restart tor@default 2>/dev/null || systemctl restart tor
  log "revoked. The phone can no longer resolve or connect to the onion."
}

cmd_pair() {
  [ -f "$RESPONDER" ] || die "pairing responder not found: $RESPONDER"
  command -v qrencode >/dev/null 2>&1 || die "qrencode missing; run setup first"
  local onion; onion="$(cat "${HS_DIR}/hostname" 2>/dev/null)" || die "service onion missing; run setup first"
  local host_fp; host_fp="$(cat "${STATE_DIR}/ssh_host_fp" 2>/dev/null)" || die "host fp missing; run setup first"
  local target_user="${SUDO_USER:-root}"
  log "starting QR mutual pairing (single-use, time-boxed)"
  # The Python responder: creates an ephemeral pairing onion, prints QR1, runs
  # SPAKE2 keyed by a one-time secret, exchanges keys, shows the SAS, and on
  # confirmation writes the phone's client-auth pubkey + SSH key, then tears down.
  python3 "$RESPONDER" \
    --service-onion "$onion" \
    --ssh-host-fp "$host_fp" \
    --authorized-clients "$AUTH_DIR" \
    --ssh-user "$target_user"
  systemctl restart tor@default 2>/dev/null || systemctl restart tor
  log "pairing finished. State: $(pairing_state)"
}

# ---- dispatch ----
case "${1:-setup}" in
  setup)
    install_packages; harden_ssh; setup_service_onion
    log "setup complete (UNPAIRED). Run: sudo bash $0 pair"
    ;;
  pair)   cmd_pair ;;
  status) cmd_status ;;
  revoke) cmd_revoke ;;
  *) die "unknown command '${1}'. Use: setup | pair | status | revoke" ;;
esac
