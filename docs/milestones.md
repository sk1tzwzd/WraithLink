# Release milestones (sequencing)

This is the ship order from the “traps vs real goals” plan. Do not reorder casually.

## Milestone 1 — lean OS (current published)

**Goal:** Flashable Pixel image with *your* keys and *your* update servers.

- Rebrand + Setup wizard (panic wipe, USB, 2G, Mullvad DNS one-tap, WraithVault create)
- Own signing keys / AVB / OTA URL (never grapheneos.org for updates)
- Media metadata strip (`WL_ENABLE_MEDIA_PRIVACY=true`)
- F-Droid preinstalled; Orbot / Tor Browser / Mullvad via F-Droid
- Web installer + static OTA on your domain
- Docs match reality (no Ghost / hidden-vault claims on lean images)

**Gated off on lean config:** `WL_ENABLE_DECOY_DURESS=false`, `WL_BUNDLE_DNSCRYPT=false`, `WL_APPS_REPO_HOST=""`.

Keep [`config/wraithlink.conf`](../config/wraithlink.conf) / [`wraithlink-akita.conf`](../config/wraithlink-akita.conf) decoy-false so installer publishes stay lean.

## Milestone 1b — messenger

**Goal:** WraithLink Chat in the image or first OTA.

- Stage via `apps/chat/build-and-stage.sh` from sibling WraithLink-Messenger (dedicated chat keystore)
- Real-device Tor + SAS pairing QA
- Leave `IdentityAnchor` off / unadvertised

Chat iterates as an APK; it does not require a full OS redesign.

## Milestone 2 — decoy PIN (vault wipe on coercion unlock)

**Goal:** Separate credential for *coercion-while-watching*: unlocks the everyday phone while silently destroying WraithVault. **Does not replace** GrapheneOS panic wipe.

Three credentials remain distinct: owner PIN, panic wipe, decoy PIN. See [`docs/duress.md`](duress.md).

1. Use dedicated config [`config/wraithlink-decoy.conf`](../config/wraithlink-decoy.conf) (`WL_ENABLE_DECOY_DURESS=true`) — do not flip lean conf until QA passes
2. `WL_CONFIG=…/wraithlink-decoy.conf scripts/04-apply-rebrand.sh` (locksettings patch + `ro.wraithlink.decoy=1` + aggregate include)
3. `scripts/decoy-preflight.sh` then rebuild + resign
4. On a real Pixel, complete [`docs/duress.md`](duress.md) / [`docs/decoy-qa.md`](decoy-qa.md)
5. Only then `scripts/07-deploy-site.sh` for that build and advertise decoy on the site

Setup hard-gates decoy arming on backup ack (`wraithlink_vault_backup_acked`).

Vault UI-hiding (if pursued) comes **after** decoy is trusted on hardware.

## Later (only if still wanted)

- Tor “Ghost” profile as Setup-created secondary user
- Real `apps.${WL_DOMAIN}` mirror (`WL_APPS_REPO_HOST`)
- dnscrypt-proxy binary/service (not just the toml)
- Push-wipe remote kill on a separate VPS
- Non-Pixel ports (out of scope for verified-boot story)
