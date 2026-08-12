#!/usr/bin/env bash
# Applies WraithLink framework-level patches to the synced tree.
#
# GATED: the decoy-duress patch touches security-critical lock-screen code, so it
# is OFF unless WL_ENABLE_DECOY_DURESS=true in config/wraithlink.conf. This lets
# the base image build and ship first (anti-loop), then the decoy-duress milestone
# is enabled and validated on its own rebuild. Idempotent.
. "$(cd "$(dirname "$0")/../scripts" && pwd)/lib.sh"
load_config

SRC="${1:-$WL_SRC_DIR}"
[ -d "$SRC" ] || die "Source dir not found: $SRC"

if [ "${WL_ENABLE_DECOY_DURESS:-false}" != "true" ]; then
  warn "Decoy-duress framework patch DISABLED (set WL_ENABLE_DECOY_DURESS=true to enable). Skipping."
  # Ensure any stale decoy prop fragment is removed so the base build is clean.
  rm -f "${SRC}/vendor/wraithlink/wraithlink-decoy.mk" 2>/dev/null || true
  exit 0
fi

log "Applying decoy-duress framework patch (WL_ENABLE_DECOY_DURESS=true)"
python3 "${WL_ROOT}/overlays/framework-patches/apply-decoy-duress.py" "$SRC" || die "decoy-duress patch failed"

# Advertise the capability so the WraithLink Setup wizard shows the decoy step.
mk="${SRC}/vendor/wraithlink/wraithlink-decoy.mk"
mkdir -p "$(dirname "$mk")"
{
  echo "# WraithLink decoy-duress capability flag (generated)."
  echo "PRODUCT_PRODUCT_PROPERTIES += ro.wraithlink.decoy=1"
} > "$mk"

ok "Decoy-duress framework patch applied and advertised (ro.wraithlink.decoy=1)."
