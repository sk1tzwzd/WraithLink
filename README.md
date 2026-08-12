# WraithLink

Privacy-hardened mobile OS toolkit: rebranded [GrapheneOS](https://grapheneos.org) for Google Pixels, a [LineageOS](https://lineageos.org) sibling for more devices, and build/distribution automation.

**Live site:** [https://www.wraithlink.com](https://www.wraithlink.com)  
**Messenger (separate repo):** [WraithLink-Messenger](https://github.com/sk1tzwzd/WraithLink-Messenger)

> This repository is the **toolkit** — scripts, overlays, Setup app, Lineage edition, and static site. It does **not** contain AOSP/GrapheneOS source trees, signing keys, or prebuilt factory images.

## Pixel edition (GrapheneOS-based)

Targets **Pixel 9 (`tokay`)** and **Pixel 8a (`akita`)** on Android 17 / GrapheneOS.

| Feature | Summary |
|---|---|
| Panic wipe | Surfaces GrapheneOS’s SE key-destroying duress password (full device wipe) |
| WraithVault | Secondary user profile for sensitive apps/data (back up off-phone) |
| Setup wizard | First-boot hardening: screen lock, USB, 2G, Mullvad DNS, vault |
| Media metadata strip | GPS / device / timestamp metadata removed when media is indexed |
| Own keys / OTA / installer | Your signing keys, OTA server, and WebUSB installer |
| F-Droid | Preinstalled for Orbot, Tor Browser, Mullvad VPN, etc. |
| Decoy PIN | Coercion unlock that drops WraithVault — **M2 / gated** (`config/wraithlink-decoy.conf`) |
| X47 link | Pair one phone to one [X47 Ubuntu](https://github.com/sk1tzwzd/ubuntu-x47-build) desktop over Tor + client auth |

GrapheneOS already provides per-connection MAC randomization, Camera EXIF strip, sandboxed Play (offer-only), Updater, and verified boot — WraithLink surfaces these rather than reinventing them.

Factory images and the WebUSB installer: [https://www.wraithlink.com/install/](https://www.wraithlink.com/install/)

## Lineage edition

Weaker boot / verified-boot story than Pixel Graphene builds. Same messenger APK path; soft-panic via Setup (software wipe, not SE key destroy).

| Path | Status |
|---|---|
| Fairphone 5 (`FP5`) | Full unofficial ROM published on the site |
| Other codenames | Stock Lineage + sideload messenger APK (see site `devices.json`) |

Docs and downloads: [https://www.wraithlink.com/lineage/](https://www.wraithlink.com/lineage/) · tooling under [`lineage/`](lineage/)

## Messenger

Not bundled as source in this repo. Clone the sibling project and point builds at it:

- **Repo:** [github.com/sk1tzwzd/WraithLink-Messenger](https://github.com/sk1tzwzd/WraithLink-Messenger)
- **Download:** [https://www.wraithlink.com/downloads/](https://www.wraithlink.com/downloads/)
- **Build hook:** `apps/chat/build-and-stage.sh` resolves `WL_CHAT_SRC` or `../WraithLink-Messenger`

E2EE P2P over Tor, Android 14+, Orbot recommended. Threat model: [`docs/chat.md`](docs/chat.md).

## What this repo is / is not

| Is | Is not |
|---|---|
| Build scripts, rebrand, overlays, Setup | AOSP / Graphene / Lineage source (`repo` syncs that) |
| Lineage device overlays + stage scripts | Signing keys (`keys/`, `*.jks`, `*.pem`) |
| Static site under `distribution/site/` (no APKs in git) | Prebuilt factories / OTAs (hosted on the site) |
| Config **examples** + non-secret device configs | `config/wraithlink.conf` with local paths/secrets |

## Quick start (build server)

```bash
git clone https://github.com/sk1tzwzd/WraithLink.git
git clone https://github.com/sk1tzwzd/WraithLink-Messenger.git   # sibling
cd WraithLink
cp config/wraithlink.conf.example config/wraithlink.conf   # then edit
./scripts/00-setup-build-env.sh
./scripts/01-sync-source.sh
./scripts/02-extract-vendor.sh
./scripts/03-gen-keys.sh            # BACK UP keys/ offline — docs/keys-backup.md
./scripts/04-apply-rebrand.sh
./scripts/05-build.sh
./scripts/06-generate-release.sh
./scripts/07-deploy-site.sh
```

Or `./scripts/build-all.sh`. Requirements: Debian 12 / Ubuntu 24.04+, **32+ GiB RAM** (64+ recommended), ~136 GiB source + 100+ GiB out, 16+ cores.

## Repository layout

```
config/         build config examples (device, privacy flags, milestones)
scripts/        ordered Pixel/Graphene build automation
rebrand/        branding map + rename engine + assets
overlays/       framework / media / first-boot patches
apps/           Setup app; chat/ is a stub + stage script for Messenger
lineage/        Lineage edition scripts, overlays, docs
x47-link/       phone remote-client helpers + X47-side pairing module
distribution/   OTA notes, CI sample, static site (installer + docs)
docs/           subsystem documentation
```

## Milestones

See [`docs/milestones.md`](docs/milestones.md).

- **M1:** lean OS + own OTA/installer (decoy / Ghost / dnscrypt gated off)
- **M1b:** messenger in image or first OTA
- **M2:** decoy PIN — coercion unlock that drops WraithVault

## License

Apache-2.0 for WraithLink-authored code ([`LICENSE`](LICENSE)). Upstream components retain their own licenses ([`NOTICE`](NOTICE)).
