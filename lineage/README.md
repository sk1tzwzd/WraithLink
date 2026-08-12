# WraithLink Lineage

Wide-device edition of WraithLink built on [LineageOS](https://lineageos.org).
**Weaker security model than Pixel / GrapheneOS WraithLink** — unlocked bootloaders
on most phones, interruptible software wipe only, no Titan/SE key-destroying duress,
no custom AVB relock story. See [docs/security.md](docs/security.md).

## What you get

- **WraithLink messenger** (Tor P2P) — in every ROM build *and* as a standalone APK
- Setup wizard — vault (secondary user), Mullvad DNS one-tap, soft panic wipe
- F-Droid preinstalled on ROM builds
- Coverage goal: every **official** Lineage device (full zip when CI builds it;
  messenger + Setup APKs on stock Lineage otherwise)

## Layout

| Path | Role |
|---|---|
| `config/` | Build config example |
| `docs/` | Security model + flash notes |
| `apps/setup/` | Lineage Setup (soft panic, no GrapheneOS duress) |
| `vendor-overlay/` | Product fragments copied into a Lineage tree |
| `scripts/` | sync / build-device / stage-apps / publish / matrix |
| `../distribution/site/lineage/` | Public download + honesty pages |

## Quick start (build host)

```bash
cp lineage/config/wraithlink-lineage.conf.example lineage/config/wraithlink-lineage.conf
# edit WL_LINEAGE_BRANCH, WL_SRC_DIR, device list

export WL_CONFIG="$PWD/lineage/config/wraithlink-lineage.conf"
bash lineage/scripts/01-sync.sh
bash lineage/scripts/02-stage-apps.sh          # messenger + Setup into vendor overlay
bash lineage/scripts/03-build-device.sh bacon  # example official codename
bash lineage/scripts/04-publish.sh bacon
```

Pixel / GrapheneOS builds stay under the top-level `scripts/` — do not mix `out/` trees.
