#!/usr/bin/env bash
# Sync LineageOS source (separate tree from GrapheneOS).
. "$(dirname "$0")/lib.sh"
load_lineage_config

mkdir -p "$WL_SRC_DIR"
cd "$WL_SRC_DIR"

if [ ! -d .repo ]; then
  log "repo init ${WL_MANIFEST_URL} -b ${WL_LINEAGE_BRANCH}"
  repo init -u "$WL_MANIFEST_URL" -b "$WL_LINEAGE_BRANCH" --git-lfs
fi

# TheMuppets vendor blobs use Git LFS; without git-lfs, radio/*.img are 100-byte pointers
# and brunch fails with SHA1 mismatch.
if ! command -v git-lfs >/dev/null 2>&1; then
  die "git-lfs is required (apt install git-lfs). Vendor radio images are LFS objects."
fi
git lfs install >/dev/null 2>&1 || true

# Device + vendor local manifests (e.g. FP5 + TheMuppets)
MANIFEST_SRC="${WL_LINEAGE_ROOT}/local_manifests"
if [ -d "$MANIFEST_SRC" ]; then
  mkdir -p .repo/local_manifests
  rsync -a "${MANIFEST_SRC}/" .repo/local_manifests/
  ok "Installed local_manifests from lineage/local_manifests/"
fi

log "repo sync -j${WL_SYNC_JOBS}"
repo sync -c -j"${WL_SYNC_JOBS}" --force-sync --no-clone-bundle --no-tags

# Ensure LFS objects materialize (vendor radio imgs + chromium-webview APKs).
log "git lfs pull for known LFS projects"
repo forall -c 'git lfs pull' 2>/dev/null || {
  for d in \
    vendor/fairphone/FP5 \
    external/chromium-webview/prebuilt/arm \
    external/chromium-webview/prebuilt/arm64 \
    external/chromium-webview/prebuilt/x86 \
    external/chromium-webview/prebuilt/x86_64
  do
    if [ -e "${WL_SRC_DIR}/${d}/.git" ] || [ -e "${WL_SRC_DIR}/${d}/.gitattributes" ]; then
      log "git lfs pull -> ${d}"
      (cd "${WL_SRC_DIR}/${d}" && git lfs pull) || warn "git lfs pull failed in ${d}"
    fi
  done
}

ok "Lineage tree ready at ${WL_SRC_DIR}. Next: lineage/scripts/02-stage-apps.sh"
