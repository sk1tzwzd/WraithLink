#!/usr/bin/env bash
# Strip sensitive media metadata at MediaStore index time (default ON).
# Covers camera captures, downloads, messaging attachments, and anything else
# MediaProvider scans. Disable per-device via Settings.Secure
# wraithlink_strip_media_metadata=0 (or set WL_ENABLE_MEDIA_PRIVACY=false to skip
# the framework patch entirely).
. "$(cd "$(dirname "$0")/../scripts" && pwd)/lib.sh"
load_config

SRC="${1:-$WL_SRC_DIR}"
[ -d "$SRC" ] || die "Source dir not found: $SRC"

if [ "${WL_ENABLE_MEDIA_PRIVACY:-true}" != "true" ]; then
  warn "Media-privacy patch DISABLED (WL_ENABLE_MEDIA_PRIVACY!=true). Skipping."
  rm -f "${SRC}/vendor/wraithlink/wraithlink-mediaprivacy.mk" 2>/dev/null || true
  exit 0
fi

log "Applying media-metadata strip patch (WL_ENABLE_MEDIA_PRIVACY=true)"
python3 "${WL_ROOT}/overlays/framework-patches/apply-media-privacy.py" "$SRC" \
  || die "media-privacy patch failed"

mk="${SRC}/vendor/wraithlink/wraithlink-mediaprivacy.mk"
mkdir -p "$(dirname "$mk")"
{
  echo "# WraithLink media-privacy capability flag (generated)."
  echo "PRODUCT_PRODUCT_PROPERTIES += ro.wraithlink.strip_media_metadata=1"
} > "$mk"

ok "Media-privacy patch applied (ro.wraithlink.strip_media_metadata=1)."
