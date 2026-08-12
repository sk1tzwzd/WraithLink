#!/usr/bin/env bash
# Run the full WraithLink pipeline end-to-end on the build server.
# Each step is safe to re-run; long steps (sync/build) resume where possible.
. "$(dirname "$0")/lib.sh"
load_config

HERE="$(dirname "$0")"
log "WraithLink full build for ${WL_DEVICE} (${WL_BRANCH})"

"${HERE}/00-setup-build-env.sh"
"${HERE}/01-sync-source.sh"
"${HERE}/02-extract-vendor.sh"
[ -d "$WL_KEYS_DIR" ] && [ -n "$(ls -A "$WL_KEYS_DIR" 2>/dev/null)" ] \
  && warn "Keys already exist; skipping key generation." \
  || "${HERE}/03-gen-keys.sh"
"${HERE}/04-apply-rebrand.sh"
"${HERE}/05-build.sh"
"${HERE}/06-generate-release.sh" "$@"

ok "WraithLink pipeline finished."
