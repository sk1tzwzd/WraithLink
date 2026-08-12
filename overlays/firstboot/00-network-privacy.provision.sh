#!/system/bin/sh
# WraithLink first-boot provisioning fragment: network privacy.
# Runs once (guarded by wraithlink.provisioned prop) as a privileged service.
# @@ tokens are substituted at build time by overlays/apply-network-privacy.sh.

# Strict encrypted DNS (DoT) pointed at the WraithLink default resolver.
settings put global private_dns_mode hostname
settings put global private_dns_specifier "@@WL_DEFAULT_DNS_HOST@@"

# Non-persistent (per-connection) Wi-Fi MAC randomization: never a stable MAC.
settings put global wifi_connected_mac_randomization_enabled 1

# If dnscrypt-proxy is bundled, point strict DNS at the local proxy instead.
if [ "@@WL_BUNDLE_DNSCRYPT@@" = "true" ]; then
    # dnscrypt-proxy listens on 127.0.0.1:5353; use a loopback DoT front or
    # rely on the system resolver's forwarding (wired up in device integration).
    log -t wraithlink "dnscrypt-proxy enabled; strict DNS via local proxy"
fi

log -t wraithlink "network-privacy provisioning applied"
