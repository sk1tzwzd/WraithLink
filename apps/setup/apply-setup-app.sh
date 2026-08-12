#!/usr/bin/env bash
# Installs the WraithLink Setup wizard into the source tree as an in-tree,
# platform-signed android_app module and registers it in PRODUCT_PACKAGES.
# Idempotent. Invoked by scripts/04-apply-rebrand.sh with SRC as $1.
. "$(cd "$(dirname "$0")/../../scripts" && pwd)/lib.sh"
load_config

SRC="${1:-$WL_SRC_DIR}"
[ -d "$SRC" ] || die "Source dir not found: $SRC"

APP_SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${SRC}/packages/apps/WraithLinkSetup"

log "Installing WraithLink Setup app -> ${DEST}"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "${APP_SRC}/Android.bp" "${APP_SRC}/AndroidManifest.xml" "${APP_SRC}/res" "${APP_SRC}/src" "$DEST/"

mk="${SRC}/vendor/wraithlink/wraithlink-setup.mk"
mkdir -p "$(dirname "$mk")"
{
  echo "# WraithLink Setup wizard product fragment (generated)."
  echo "PRODUCT_PACKAGES += WraithLinkSetup"
} > "$mk"

ok "WraithLink Setup app staged and registered (PRODUCT_PACKAGES += WraithLinkSetup)."
