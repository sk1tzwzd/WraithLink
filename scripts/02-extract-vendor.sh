#!/usr/bin/env bash
# Phase 0: extract Pixel vendor files with adevtool (Pixel targets only).
# Reference: https://grapheneos.org/build#extracting-vendor-files-for-pixel-devices
. "$(dirname "$0")/lib.sh"
load_config

cd "$WL_SRC_DIR" || die "Source not found at ${WL_SRC_DIR} - run 01-sync-source.sh first."

log "Installing adevtool deps (yarnpkg)..."
# On Debian, 'yarn' is cmdtest; use yarnpkg for the actual package manager.
if command -v yarnpkg >/dev/null 2>&1; then
  yarnpkg --cwd vendor/adevtool/ install
else
  yarn --cwd vendor/adevtool/ install
fi

log "Extracting/preparing vendor files for device: ${WL_DEVICE}"
# adevtool downloads the official factory images and extracts proprietary blobs.
./vendor/adevtool/bin/run generate-all -d "$WL_DEVICE" \
  || adevtool generate-all -d "$WL_DEVICE" \
  || die "adevtool failed for ${WL_DEVICE}. Check the codename is a supported Pixel."

ok "Vendor files ready for ${WL_DEVICE}. Next: scripts/03-gen-keys.sh"
