#!/usr/bin/env bash
# Phase 10: co-host the WraithLink static site + OTA + factory images on the
# build server behind Caddy (automatic Let's Encrypt HTTPS). Idempotent.
#
# Run this ON the server (the repo is already synced there). It:
#   - installs Caddy if missing,
#   - renders the Caddyfile for your domain,
#   - publishes distribution/site/ to /srv/wraithlink-www,
#   - publishes any signed release (OTA zip + channel metadata + factory image)
#     and updates the installer's release.json,
#   - firewalls to 80/443 + SSH,
#   - reloads Caddy and prints the DNS records to set.
#
# Security: only the three static /srv roots are served. keys/ and the source
# tree stay in the builder's home dir, never under /srv.
. "$(dirname "$0")/lib.sh"
load_config

WWW="/srv/wraithlink-www"
OTA="/srv/wraithlink-ota"
RELEASES="/srv/wraithlink-releases"
APPS="/srv/wraithlink-apps"
SITE_SRC="${WL_ROOT}/distribution/site"
EMAIL="${WL_ACME_EMAIL:-admin@${WL_DOMAIN}}"

[ -d "$SITE_SRC" ] || die "Site not found at ${SITE_SRC}."
[ "$WL_DOMAIN" != "wraithlink.example" ] || warn "WL_DOMAIN is still the placeholder; edit config/wraithlink.conf."

# ---- 1. Install Caddy (official apt repo) if not present ----
if ! command -v caddy >/dev/null 2>&1; then
  log "Installing Caddy"
  sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y caddy
else
  ok "Caddy already installed ($(caddy version | head -1))"
fi

# ---- 2. Render the Caddyfile ----
log "Rendering /etc/caddy/Caddyfile for ${WL_DOMAIN}"
tmp="$(mktemp)"
sed -e "s#@@WL_DOMAIN@@#${WL_DOMAIN}#g" -e "s#@@WL_EMAIL@@#${EMAIL}#g" \
  "${WL_ROOT}/distribution/deploy/Caddyfile.template" > "$tmp"
sudo install -m 0644 "$tmp" /etc/caddy/Caddyfile
rm -f "$tmp"

# ---- 3. Publish the static site ----
log "Publishing site -> ${WWW}"
sudo mkdir -p "$WWW" "$OTA" "$RELEASES" "$APPS"
sudo rsync -a --delete "${SITE_SRC}/" "$WWW/"
# Factory images live under /srv/wraithlink-releases; expose them on www so the
# installer works even when the releases. subdomain has no DNS yet.
sudo rm -rf "${WWW}/releases"
sudo ln -sfn "$RELEASES" "${WWW}/releases"

# ---- 4. Publish a signed release if one exists ----
LATEST_REL="$(ls -1dt "${WL_SRC_DIR}/releases/"*/release-"${WL_DEVICE}"-* 2>/dev/null | head -1 || true)"
if [ -n "$LATEST_REL" ] && [ -d "$LATEST_REL" ]; then
  build="$(basename "$(dirname "$LATEST_REL")")"
  log "Publishing release ${build} from ${LATEST_REL}"
  # OTA package + channel metadata
  ota_zip="$(ls -1 "${LATEST_REL}"/*ota_update*.zip 2>/dev/null | head -1 || true)"
  if [ -n "$ota_zip" ]; then
    sudo mkdir -p "${OTA}/${build}"
    sudo cp -f "$ota_zip" "${OTA}/${build}/"
    # channel metadata file (e.g. tokay-stable) if present in release dir
    for meta in "${LATEST_REL}/${WL_DEVICE}-stable" "${LATEST_REL}/${WL_DEVICE}-beta"; do
      [ -f "$meta" ] && sudo cp -f "$meta" "${OTA}/"
    done
  fi
  # Factory image for the web installer. Merge into existing release.json so
  # multiple devices (tokay + akita, etc.) can be published side by side.
  factory_zip="$(ls -1 "${LATEST_REL}"/*factory*.zip 2>/dev/null | head -1 || true)"
  if [ -n "$factory_zip" ]; then
    sudo mkdir -p "${RELEASES}/${build}"
    sudo cp -f "$factory_zip" "${RELEASES}/${build}/"
    fz="$(basename "$factory_zip")"
    sha="$(sha256sum "$factory_zip" | awk '{print $1}')"
    # Prefer www path so flash works even before releases. subdomain DNS exists.
    url="https://www.${WL_DOMAIN}/releases/${build}/${fz}"
    rel_json="${WWW}/install/release.json"
    # Preserve sibling device entries; never concatenate version strings.
    sudo python3 - "$rel_json" "$build" "$WL_DEVICE" "$url" "$sha" <<'PY'
import json, sys, os
path, build, device, url, sha = sys.argv[1:6]
data = {"published": True, "version": build, "devices": {}}
if os.path.isfile(path):
    try:
        with open(path) as f:
            prev = json.load(f)
        if isinstance(prev, dict):
            data["devices"] = dict(prev.get("devices") or {})
    except Exception:
        pass
data["published"] = True
data["version"] = build
data["devices"][device] = {"factory_zip": url, "sha256": sha, "build": build}
# Also keep a copy in the toolkit site tree so rsync --delete cannot regress URLs.
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"wrote {path} devices={list(data['devices'])}")
PY
    # Mirror into toolkit so the next --delete rsync keeps installer metadata.
    stub_json="${SITE_SRC}/install/release.json"
    mkdir -p "$(dirname "$stub_json")"
    sudo cp -f "$rel_json" "$stub_json" 2>/dev/null || cp -f "$rel_json" "$stub_json"
    ok "Installer release.json includes ${WL_DEVICE} -> www.${WL_DOMAIN}/releases/${build}/${fz}"
  fi
else
  warn "No signed release found yet (run scripts/06-generate-release.sh). Site deploys; installer shows 'coming soon'."
fi

# ---- 5. Firewall: 80/443 + SSH only ----
if command -v ufw >/dev/null 2>&1; then
  log "Configuring ufw (allow SSH, 80, 443)"
  sudo ufw allow OpenSSH >/dev/null 2>&1 || sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw --force enable
fi

# ---- 6. Reload Caddy ----
log "Validating + reloading Caddy"
sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy || sudo systemctl restart caddy
sudo systemctl enable caddy >/dev/null 2>&1 || true

SERVER_IP="$(curl -fsS https://api.ipify.org 2>/dev/null || echo '<server-ip>')"
cat <<EOF

$(ok "Deploy complete.")

Point these DNS records at the server (${SERVER_IP}):

  A     ${WL_DOMAIN}            ${SERVER_IP}
  A     www.${WL_DOMAIN}        ${SERVER_IP}
  A     ota.${WL_DOMAIN}        ${SERVER_IP}
  A     releases.${WL_DOMAIN}   ${SERVER_IP}
  A     apps.${WL_DOMAIN}       ${SERVER_IP}
  # add matching AAAA records if the server has an IPv6 address

Caddy obtains Let's Encrypt certificates automatically once DNS resolves here.
To deploy from a workstation instead, rsync the site up first:
  rsync -a distribution/site/ builder@${SERVER_IP}:/srv/wraithlink-www/
EOF
