#!/usr/bin/env bash
# Phase 3: static network-privacy defaults (encrypted DNS mode + no-persistent-MAC).
# The runtime settings (DNS specifier host, MAC toggle) are applied by the shared
# first-boot runner via overlays/firstboot/00-network-privacy.provision.sh.
# Idempotent. Invoked by scripts/04-apply-rebrand.sh with SRC as $1.
. "$(cd "$(dirname "$0")/../scripts" && pwd)/lib.sh"
load_config

SRC="${1:-$WL_SRC_DIR}"
OV_SRC="${WL_ROOT}/overlays/wraithlink-overlay"
OV_DEST="${SRC}/vendor/wraithlink/overlay"
[ -d "$SRC" ] || die "Source dir not found: $SRC"

# Keep the overlay resources in the tree for the future standalone RRO, but do
# NOT wire them via PRODUCT_PACKAGE_OVERLAYS: on adevtool-based Pixel targets that
# auto-generates framework-res/SettingsProvider RROs on the product partition with
# the SAME names as adevtool's vendor RROs, causing a soong_filesystem_creator
# packaging conflict. Also, forcing def_private_dns_mode=hostname WITHOUT a
# specifier can break DNS on first boot. The Mullvad-DoT default will be re-added
# as a properly-named runtime_resource_overlay (mode + specifier together).
log "Staging network-privacy overlay resources (unwired) -> ${OV_DEST}"
mkdir -p "$OV_DEST"
cp -a "${OV_SRC}/." "$OV_DEST/"

mk="${SRC}/vendor/wraithlink/wraithlink-netpriv.mk"
mkdir -p "$(dirname "$mk")"
{
  echo "# WraithLink network-privacy product fragment (generated)."
  echo "# PRODUCT_PACKAGE_OVERLAYS intentionally NOT set (see apply-network-privacy.sh)."
  echo "# MAC randomization is already a GrapheneOS default; Mullvad-DoT default is"
  echo "# pending a standalone RRO. See docs/network-privacy.md."
} > "$mk"

if [ "${WL_BUNDLE_DNSCRYPT}" = "true" ]; then
  log "Bundling dnscrypt-proxy config"
  mkdir -p "${SRC}/vendor/wraithlink/etc"
  cp "${WL_ROOT}/overlays/network-privacy/dnscrypt-proxy.toml" "${SRC}/vendor/wraithlink/etc/"
  echo "PRODUCT_COPY_FILES += vendor/wraithlink/etc/dnscrypt-proxy.toml:system/etc/wraithlink/dnscrypt-proxy.toml" >> "$mk"
fi

ok "Network-privacy overlay staged (unwired; RRO pending). MAC randomization uses GrapheneOS defaults."
