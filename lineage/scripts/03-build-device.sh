#!/usr/bin/env bash
# breakfast + brunch one official Lineage codename with WraithLink overlay injected.
. "$(dirname "$0")/lib.sh"
load_lineage_config

DEVICE="${1:-}"
[ -n "$DEVICE" ] || die "Usage: $0 <lineage-codename>"

SRC="$WL_SRC_DIR"
cd "$SRC" || die "Missing ${SRC}"

# Ensure overlay staged
[ -f "${SRC}/vendor/wraithlink-lineage/wraithlink.mk" ] \
  || die "Overlay missing — run lineage/scripts/02-stage-apps.sh first"

# Fail fast if vendor radio images are still Git LFS pointers (common FP5 footgun).
if [ -d "${SRC}/vendor/fairphone/${DEVICE}/radio" ]; then
  for img in "${SRC}/vendor/fairphone/${DEVICE}/radio/"*.img; do
    [ -f "$img" ] || continue
    if head -c 40 "$img" 2>/dev/null | grep -q 'git-lfs'; then
      die "LFS pointer still present: ${img#"${SRC}/"} — run: (cd vendor/fairphone/${DEVICE} && git lfs pull)"
    fi
  done
fi

# Inject inherit into device product makefile if present
inject_inherit() {
  local mk="$1"
  [ -f "$mk" ] || return 1
  if grep -qF "vendor/wraithlink-lineage/wraithlink.mk" "$mk"; then
    ok "Already inherits wraithlink-lineage (${mk#${SRC}/})"
    return 0
  fi
  printf '\n# WraithLink Lineage customizations\n$(call inherit-product-if-exists, vendor/wraithlink-lineage/wraithlink.mk)\n' >> "$mk"
  ok "Injected inherit into ${mk#${SRC}/}"
}

# Common Lineage product makefile locations after breakfast
for cand in \
  "device/*/${DEVICE}/lineage_${DEVICE}.mk" \
  "device/*/${DEVICE}/aosp_${DEVICE}.mk" \
  "vendor/lineage/config/"*; do
  :
done

# envsetup / breakfast / brunch are incompatible with nounset (lib.sh uses set -u).
export TOP="${TOP:-$SRC}"
set +u
# shellcheck disable=SC1091
source build/envsetup.sh
log "breakfast ${DEVICE}"
breakfast "$DEVICE" || die "breakfast ${DEVICE} failed (not official / roomservice failed?)"

# After breakfast, find lineage_${DEVICE}.mk
DEV_MK="$(find device vendor -path "*${DEVICE}*lineage_${DEVICE}.mk" 2>/dev/null | head -1 || true)"
if [ -z "$DEV_MK" ]; then
  DEV_MK="$(find device -name "lineage_${DEVICE}.mk" 2>/dev/null | head -1 || true)"
fi
if [ -n "$DEV_MK" ]; then
  inject_inherit "$DEV_MK"
else
  warn "Could not locate lineage_${DEVICE}.mk — add inherit manually before brunch"
fi

log "brunch ${DEVICE}"
brunch "$DEVICE" || die "brunch ${DEVICE} failed"
# Stay without nounset until after brunch; build functions leave unbound vars.

OUT_ZIP="$(ls -1t "${SRC}/out/target/product/${DEVICE}/lineage-"*.zip 2>/dev/null | head -1 || true)"
[ -n "$OUT_ZIP" ] || die "No lineage-*.zip found under out/target/product/${DEVICE}"
ok "Build OK: ${OUT_ZIP}"
echo "$OUT_ZIP"
