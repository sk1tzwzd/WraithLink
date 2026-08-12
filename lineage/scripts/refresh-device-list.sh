#!/usr/bin/env bash
# Refresh lineage/devices/official.txt from LineageOS hudson device list (best-effort).
. "$(dirname "$0")/lib.sh"

OUT="${WL_LINEAGE_ROOT}/devices/official.txt"
URL="${WL_LINEAGE_DEVICES_URL:-https://raw.githubusercontent.com/LineageOS/hudson/main/updater/devices.json}"

tmp="$(mktemp)"
if ! curl -fsSL "$URL" -o "$tmp"; then
  warn "Could not fetch ${URL}; leaving ${OUT} unchanged"
  rm -f "$tmp"
  exit 0
fi

python3 - "$tmp" "$OUT" <<'PY'
import json, sys
src, out = sys.argv[1:3]
try:
    data = json.load(open(src))
except Exception as e:
    print("parse failed", e)
    sys.exit(0)
models = []
# hudson format varies; accept list of dicts with model/codename
if isinstance(data, list):
    for item in data:
        if not isinstance(item, dict):
            continue
        m = item.get("model") or item.get("codename") or item.get("name")
        if m and isinstance(m, str) and m.replace("_", "").isalnum():
            models.append(m)
elif isinstance(data, dict):
    for k, v in data.items():
        if isinstance(v, dict):
            models.append(k)
models = sorted(set(models))
with open(out, "w") as f:
    f.write("# Auto-refreshed from Lineage hudson devices.json — edit allowlist via WL_DEVICE_ALLOWLIST\n")
    for m in models:
        f.write(m + "\n")
print(f"wrote {len(models)} devices to {out}")
PY
rm -f "$tmp"
ok "Device list refresh attempted -> ${OUT}"
