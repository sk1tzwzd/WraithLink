#!/usr/bin/env bash
# Phase 8: wire the phone-side X47 remote client into the WraithLink image.
# Exclusive linking model: Tor v3 onion + client auth, established via QR mutual
# pairing. NO onion address or keys are baked in - the phone learns them only
# during pairing. Idempotent. Invoked by scripts/04-apply-rebrand.sh with SRC $1.
. "$(cd "$(dirname "$0")/../scripts" && pwd)/lib.sh"
load_config

SRC="${1:-$WL_SRC_DIR}"
[ -d "$SRC" ] || die "Source dir not found: $SRC"

VDIR="${SRC}/vendor/wraithlink/x47"
mkdir -p "$VDIR"

[ "${WL_X47_TRANSPORT}" = "onion" ] || warn "WL_X47_TRANSPORT=${WL_X47_TRANSPORT}; exclusive linking requires 'onion'."

log "Installing X47 client config template (transport=${WL_X47_TRANSPORT}, no preset onion)"
cat > "${VDIR}/x47.conf" <<EOF
# WraithLink -> X47 remote connection profile.
# Transport is Tor v3 onion + client authorization. There is deliberately NO
# preset onion address or key here: the phone obtains the service onion, the
# pinned SSH host key, and its own client-auth key ONLY through QR pairing
# (Settings/onboarding -> Connect to X47). This is what keeps linking exclusive.
WL_X47_TRANSPORT=${WL_X47_TRANSPORT}
WL_X47_SOCKS=127.0.0.1:9050
EOF

log "Rendering 'Connect to X47' first-boot fragment (launches pairing, not a preset)"
cat > "${WL_ROOT}/overlays/firstboot/30-x47-link.provision.sh" <<'EOF'
#!/system/bin/sh
# WraithLink first-boot fragment: surface the "Connect to X47" QR pairing step.
# No credentials are provisioned here; pairing generates per-device keys on first use.
settings put secure wraithlink_onboard_x47 1
log -t wraithlink "X47 QR pairing onboarding scheduled"
EOF
chmod +x "${WL_ROOT}/overlays/firstboot/30-x47-link.provision.sh"

# Offer the pairing/remote client apps via the Store (ConnectBot, bVNC).
mk="${SRC}/vendor/wraithlink/wraithlink-x47.mk"
{
  echo "# WraithLink X47 client product fragment (generated)."
  echo "PRODUCT_COPY_FILES += vendor/wraithlink/x47/x47.conf:system/etc/wraithlink/x47.conf"
} > "$mk"

ok "X47 remote client wired (onion + client auth, QR pairing). Offer ConnectBot/bVNC via the Store."
warn "On the X47 machine: copy x47-link/x47-side/{90-wraithlink-remote.sh,wraithlink-pair-responder.py} into ubuntu-x47-build/modules/, run setup, then 'pair'."
