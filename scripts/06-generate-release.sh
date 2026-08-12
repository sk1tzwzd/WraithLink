#!/usr/bin/env bash
# Phase 9: sign the build and produce factory images + OTA update package.
# Reference: https://grapheneos.org/build#generating-signed-factory-images-and-full-update-packages
. "$(dirname "$0")/lib.sh"
load_config

cd "$WL_SRC_DIR" || die "Source not found at ${WL_SRC_DIR}."
[ -d "$WL_KEYS_DIR" ] || die "Signing keys not found at ${WL_KEYS_DIR} - run 03-gen-keys.sh."

BUILD_NUMBER="${1:-$(date -u +%Y%m%d00)}"

log "Finalizing build artifacts (script/finalize.sh)"
source build/envsetup.sh >/dev/null 2>&1 || true
script/finalize.sh

log "Generating signed release for ${WL_DEVICE} build ${BUILD_NUMBER}"
# generate-release.sh reads the (encrypted) keys from keys/<device>/ and produces
# releases/<build>/release-<device>-<build>/ with factory images + OTA zip + metadata.
script/generate-release.sh "$WL_DEVICE" "$BUILD_NUMBER"

REL="releases/${BUILD_NUMBER}/release-${WL_DEVICE}-${BUILD_NUMBER}"
ok "Release ready: ${WL_SRC_DIR}/${REL}"
log "Contents:"; ls -1 "$REL" 2>/dev/null || warn "release dir not found; check generate-release output"

cat <<EOF

Next steps:
  * Upload the OTA zip + '${WL_DEVICE}-stable' channel metadata to your OTA server (${WL_OTA_URL}).
  * Publish factory images to GitHub Releases (distribution/ci pushes them).
  * Users flash via the WraithLink web installer (distribution/web-installer).
EOF
