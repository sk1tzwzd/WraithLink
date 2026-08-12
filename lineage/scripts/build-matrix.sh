#!/usr/bin/env bash
# Sequentially build official devices (or allowlist). Failures are recorded; APK path still covers them.
. "$(dirname "$0")/lib.sh"
load_lineage_config

LIST="${WL_LINEAGE_ROOT}/devices/official.txt"
RESULTS="${WL_LINEAGE_ROOT}/devices/matrix-results.txt"
: > "$RESULTS"

devices=()
if [ -n "${WL_DEVICE_ALLOWLIST:-}" ]; then
  # shellcheck disable=SC2206
  devices=($WL_DEVICE_ALLOWLIST)
else
  while read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    devices+=("$line")
  done < "$LIST"
fi

log "Matrix: ${#devices[@]} device(s)"
bash "${WL_LINEAGE_ROOT}/scripts/02-stage-apps.sh" || warn "stage-apps had warnings"

for d in "${devices[@]}"; do
  log "=== building ${d} ==="
  if bash "${WL_LINEAGE_ROOT}/scripts/03-build-device.sh" "$d"; then
    bash "${WL_LINEAGE_ROOT}/scripts/04-publish.sh" "$d" && echo "OK ${d}" >> "$RESULTS" || echo "PUBLISH_FAIL ${d}" >> "$RESULTS"
  else
    echo "FAIL ${d}" >> "$RESULTS"
    warn "Build failed for ${d} — users can still install messenger APK on stock Lineage"
  fi
done

# Refresh devices.json APK-only stubs for failures / unbuilt
python3 - "${WL_REPO_ROOT}/distribution/site/lineage/devices.json" "$LIST" "$RESULTS" <<'PY'
import json, os, sys
path, listing, results = sys.argv[1:4]
data = {"edition": "lineage", "messenger_apk": "downloads/WraithLinkChat.apk", "devices": {}}
if os.path.isfile(path):
    try:
        data.update(json.load(open(path)))
    except Exception:
        pass
data.setdefault("devices", {})
ok = set()
if os.path.isfile(results):
    for line in open(results):
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "OK":
            ok.add(parts[1])
for line in open(listing):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if line in ok:
        continue
    data["devices"].setdefault(line, {
        "status": "apk",
        "note": "No WraithLink Lineage zip yet — install stock LineageOS, then the messenger APK.",
    })
data["messenger_apk"] = "downloads/WraithLinkChat.apk"
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("devices.json refreshed")
PY

ok "Matrix finished — see ${RESULTS}"
