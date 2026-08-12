#!/usr/bin/env bash
# Phase 0: init + sync the GrapheneOS source tree (~136 GiB).
# Reference: https://grapheneos.org/build
. "$(dirname "$0")/lib.sh"
load_config
require_cmd repo
require_cmd git

mkdir -p "$WL_SRC_DIR"
preflight_build_host "$WL_SRC_DIR"

cd "$WL_SRC_DIR"
log "repo init: ${WL_MANIFEST_URL} branch=${WL_BRANCH}"
repo init -u "$WL_MANIFEST_URL" -b "$WL_BRANCH"

# Verify manifest tag signature when a stable tag (refs/tags/...) is used.
if [[ "$WL_BRANCH" == refs/tags/* ]]; then
  log "Verifying GrapheneOS signing key + manifest tag signature..."
  curl -fsSL https://grapheneos.org/allowed_signers > "${HOME}/.ssh/grapheneos_allowed_signers"
  ( cd .repo/manifests
    git config gpg.ssh.allowedSignersFile "${HOME}/.ssh/grapheneos_allowed_signers"
    git verify-tag "$(git describe)" && ok "Manifest tag signature verified." ) \
    || die "Manifest tag signature verification FAILED - do not proceed."
fi

log "repo sync -j${WL_SYNC_JOBS} (this downloads ~136 GiB; resumable if interrupted)..."
repo sync -j"$WL_SYNC_JOBS"

ok "Source synced to ${WL_SRC_DIR}. Next: scripts/02-extract-vendor.sh"
