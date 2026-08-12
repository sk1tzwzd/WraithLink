# Network privacy

## Encrypted DNS (v1)

- Not baked as a forced product default (the SettingsProvider RRO is intentionally
  unwired to avoid adevtool naming clashes and captive-portal breakage on first boot).
- **WraithLink Setup** offers one-tap Mullvad DNS-over-TLS (`dns.mullvad.net`).
- Users can change Private DNS to any DoT host, or turn it off for captive portals.

## MAC randomization

- Relies on **GrapheneOS / AOSP per-connection Wi-Fi MAC randomization** (already strong).
- WraithLink does not claim a separate MAC overlay in v1.

## Tor / VPN apps

- Orbot, Tor Browser, and Mullvad VPN are **not** preinstalled in the lean v1 image.
- Install them from F-Droid (preinstalled) when needed.
- WraithLink Chat and X47 pairing use Tor onion services when those apps are used.

## Milestone 2 (parked)

- Re-enable a standalone network-privacy RRO for stricter baked defaults, if desired.
- Optional `dnscrypt-proxy` binary/service (`WL_BUNDLE_DNSCRYPT`; default **false** in v1 —
  only a config template exists today).
- Automated Tor "Ghost" secondary profile (not shipped; do not advertise).
