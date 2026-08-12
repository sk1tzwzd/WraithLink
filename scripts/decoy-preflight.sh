#!/usr/bin/env bash
# Host-side checks that a decoy-enabled tree / image is wired correctly.
# Does not replace Pixel hardware QA in docs/duress.md.
. "$(dirname "$0")/lib.sh"
load_config

SRC="${WL_SRC_DIR}"
fail=0
check() {
  if "$@"; then ok "$*"; else warn "FAIL: $*"; fail=1; fi
}

log "Decoy preflight (WL_DEVICE=${WL_DEVICE}, config decoy=${WL_ENABLE_DECOY_DURESS:-unset})"

if [ "${WL_ENABLE_DECOY_DURESS:-false}" != "true" ]; then
  die "WL_ENABLE_DECOY_DURESS must be true for this script (use config/wraithlink-decoy.conf)"
fi

check test -f "${SRC}/vendor/wraithlink/wraithlink-decoy.mk"
check grep -q 'ro.wraithlink.decoy=1' "${SRC}/vendor/wraithlink/wraithlink-decoy.mk"
check grep -q 'wraithlink-decoy.mk' "${SRC}/vendor/wraithlink/wraithlink.mk"

# Patch markers in locksettings (narrow paths — do not recurse all of frameworks/base)
LS_DIR="${SRC}/frameworks/base/services/core/java/com/android/server/locksettings"
HELPER="${LS_DIR}/DecoyDuressHelper.java"
DESTROY="${LS_DIR}/WraithVaultDestroy.java"
if [ -f "$HELPER" ] && [ -f "$DESTROY" ]; then
  ok "Decoy helpers present under locksettings/"
elif grep -Rql --include='*.java' 'class DecoyDuressHelper' "${SRC}/frameworks/base/services" 2>/dev/null; then
  ok "DecoyDuressHelper found under frameworks/base/services"
else
  warn "Could not find DecoyDuressHelper — confirm apply-decoy-duress.py ran"
fi

# Built prop from product out if present
PROP_OUT="${SRC}/out/target/product/${WL_DEVICE}/product/etc/build.prop"
if [ -f "$PROP_OUT" ]; then
  if grep -q 'ro.wraithlink.decoy=1' "$PROP_OUT" \
      || grep -Rql 'ro.wraithlink.decoy=1' "${SRC}/out/target/product/${WL_DEVICE}/product" 2>/dev/null; then
    ok "Product out advertises ro.wraithlink.decoy=1"
  else
    warn "Product out present but decoy prop not found yet (rebuild may be incomplete)"
  fi
else
  warn "No product out yet — run scripts/05-build.sh then re-run this script"
fi

[ "$fail" -eq 0 ] || die "Decoy preflight failed"
ok "Decoy preflight passed (still run hardware QA on a Pixel)"
