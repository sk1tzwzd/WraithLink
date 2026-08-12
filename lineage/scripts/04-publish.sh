#!/usr/bin/env bash
# Copy a built Lineage zip + update devices JSON for the download site.
. "$(dirname "$0")/lib.sh"
load_lineage_config

DEVICE="${1:-}"
[ -n "$DEVICE" ] || die "Usage: $0 <codename> [zip-path]"

SRC="$WL_SRC_DIR"
ZIP="${2:-}"
if [ -z "$ZIP" ]; then
  ZIP="$(ls -1t "${SRC}/out/target/product/${DEVICE}/lineage-"*.zip 2>/dev/null | head -1 || true)"
fi
[ -n "$ZIP" ] && [ -f "$ZIP" ] || die "No zip for ${DEVICE}"

REL="${WL_RELEASE_DIR:-${HOME}/wraithlink-lineage-releases}"
mkdir -p "${REL}/${DEVICE}"
cp -f "$ZIP" "${REL}/${DEVICE}/"
BASENAME="$(basename "$ZIP")"
SHA="$(sha256sum "${REL}/${DEVICE}/${BASENAME}" | awk '{print $1}')"
ok "Published ${BASENAME} sha256=${SHA}"

SITE_DL="${WL_REPO_ROOT}/distribution/site/lineage/downloads"
mkdir -p "${SITE_DL}/${DEVICE}"
cp -f "${REL}/${DEVICE}/${BASENAME}" "${SITE_DL}/${DEVICE}/"
echo "$SHA" > "${SITE_DL}/${DEVICE}/${BASENAME}.sha256"

# Merge into devices.json for the web UI
JSON="${WL_REPO_ROOT}/distribution/site/lineage/devices.json"
python3 - "$JSON" "$DEVICE" "$BASENAME" "$SHA" <<'PY'
import json, os, sys
path, device, name, sha = sys.argv[1:5]
data = {"edition": "lineage", "devices": {}}
if os.path.isfile(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        pass
data.setdefault("devices", {})
data["devices"][device] = {
    "status": "rom",
    "zip": f"downloads/{device}/{name}",
    "sha256": sha,
    "note": "Flash with Lineage recovery. Bootloader typically remains unlocked.",
}
# Ensure APK-only placeholder entries remain for allowlisted devices without zips
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"updated {path} -> {device}")
PY

# Optional live publish
if [ -n "${WL_SITE_LINEAGE_DIR:-}" ] && [ -d "$(dirname "$WL_SITE_LINEAGE_DIR")" ]; then
  sudo mkdir -p "$WL_SITE_LINEAGE_DIR" 2>/dev/null || mkdir -p "$WL_SITE_LINEAGE_DIR"
  rsync -a "${WL_REPO_ROOT}/distribution/site/lineage/" "${WL_SITE_LINEAGE_DIR}/" || warn "rsync to ${WL_SITE_LINEAGE_DIR} failed"
fi

ok "Site artifacts updated for ${DEVICE}"
