#!/usr/bin/env bash
# Phase 9: build the WraithLink target-files-package for the configured device.
# Reference: https://grapheneos.org/build#building
. "$(dirname "$0")/lib.sh"
load_config

cd "$WL_SRC_DIR" || die "Source not found at ${WL_SRC_DIR} - run 01-sync-source.sh first."
preflight_build_host "$WL_SRC_DIR"

log "Sourcing AOSP build environment"
# shellcheck disable=SC1091
source build/envsetup.sh

export OFFICIAL_BUILD="${WL_OFFICIAL_BUILD}"    # includes Updater (needs WL_OTA_URL)

log "lunch ${WL_DEVICE}-cur-${WL_BUILD_VARIANT}"
lunch "${WL_DEVICE}-cur-${WL_BUILD_VARIANT}"

# Device-specific extra image targets (per GrapheneOS build docs).
case "$WL_DEVICE" in
  oriole|raven|bluejay)                         EXTRA="vendorbootimage" ;;
  panther|cheetah|lynx|tangorpro|felix|\
  shiba|husky|akita|tokay|caiman|komodo|comet)  EXTRA="vendorbootimage vendorkernelbootimage" ;;
  *)                                            EXTRA="" ;;
esac

# A clean out/ gives a reproducible production build, but the rebuild-verify pass
# (applying wizard/apps/rebrand on top of an already-built tree) wants the WARM
# cache so only changed modules recompile. Set WL_INCREMENTAL=true for that.
if [ "${WL_INCREMENTAL:-false}" = "true" ]; then
  warn "Incremental build (WL_INCREMENTAL=true): keeping existing out/ (warm cache)."
else
  log "Clean out/ for a reproducible production build"
  rm -rf out
fi

log "Building: m ${EXTRA} target-files-package"
# shellcheck disable=SC2086
m ${EXTRA} target-files-package

log "Building otatools-package"
m otatools-package

ok "Build complete. Next: scripts/06-generate-release.sh"
