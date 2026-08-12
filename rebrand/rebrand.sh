#!/usr/bin/env bash
# Rebrand engine: GrapheneOS -> WraithLink, applied to a synced source tree.
# Surgical by design: renames user-visible strings, build props, assets, and the
# Updater URL. Does NOT rename package IDs (that breaks WebView/Vanadium wiring).
#
# Usage: rebrand.sh <SRC_DIR> <OTA_URL> [--apply]
#   Without --apply it runs a DRY RUN and only reports what would change.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${HERE}/branding.conf"

SRC="${1:?usage: rebrand.sh <SRC_DIR> <OTA_URL> [--apply]}"
OTA_URL="${2:?missing OTA_URL}"
APPLY="${3:-}"
DRY=1; [ "$APPLY" = "--apply" ] && DRY=0

say() { printf '  %s\n' "$*"; }
act() { if [ "$DRY" -eq 1 ]; then say "DRY: $*"; else say "DO : $*"; fi; }

[ -d "$SRC" ] || { echo "Source dir not found: $SRC" >&2; exit 1; }
cd "$SRC"

echo "== Rebrand ${OLD_NAME} -> ${NEW_NAME} (dry-run=${DRY}) =="

# 1) Rename <string> VALUES only (never the name="..." IDs) in curated resources.
#    We match >...GrapheneOS...< inside string element bodies.
echo "-- string resources --"
for glob in "${STRING_RES_GLOBS[@]}"; do
  while IFS= read -r -d '' f; do
    if grep -q ">[^<]*${OLD_NAME}[^<]*<" "$f" 2>/dev/null; then
      act "rename in $f"
      if [ "$DRY" -eq 0 ]; then
        # Only touch text between > and < so attribute IDs are never renamed.
        sed -i -E "s/(>[^<]*)${OLD_NAME}([^<]*<)/\1${NEW_NAME}\2/g" "$f"
      fi
    fi
  done < <(find . -path "./$glob" -type f -print0 2>/dev/null)
done

# 2) Repoint the Updater to your OTA server (critical: else it DoSes upstream).
echo "-- updater url --"
if [ -f "$UPDATER_CONFIG" ]; then
  act "set update server URL in $UPDATER_CONFIG -> ${OTA_URL}"
  if [ "$DRY" -eq 0 ]; then
    sed -i -E "s#(<string name=\"url\">)[^<]*(</string>)#\1${OTA_URL}\2#g" "$UPDATER_CONFIG"
  fi
else
  say "WARN: $UPDATER_CONFIG not found (Updater app layout may differ in this tag)."
fi

# 3) Build properties / banners. Append a WraithLink product overlay marker.
echo "-- build props --"
PROP_MK="build/make/target/product/wraithlink_branding.mk"
act "write product branding makefile $PROP_MK"
if [ "$DRY" -eq 0 ]; then
  mkdir -p "$(dirname "$PROP_MK")"
  cat > "$PROP_MK" <<EOF
# WraithLink branding overlay (included by device product config).
PRODUCT_PRODUCT_PROPERTIES += \\
    ro.wraithlink.branding=1 \\
    ro.product.model=${NEW_NAME}
EOF
fi

# 4) Asset replacements (boot animation, logos), if provided in rebrand/assets/.
echo "-- assets --"
for pair in "${ASSET_REPLACEMENTS[@]}"; do
  src_asset="${HERE}/assets/${pair%%::*}"
  dest="${pair##*::}"
  if [ -f "$src_asset" ]; then
    act "copy asset ${pair%%::*} -> ${dest}"
    if [ "$DRY" -eq 0 ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$src_asset" "$dest"
    fi
  else
    say "skip asset ${pair%%::*} (not present in rebrand/assets/)"
  fi
done

echo "== Rebrand pass complete (dry-run=${DRY}) =="
if [ "$DRY" -eq 1 ]; then
  echo "Re-run with --apply to make changes."
fi
exit 0
