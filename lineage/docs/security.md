# WraithLink Lineage — security model (honest)

This edition prioritizes **device coverage** over GrapheneOS-grade integrity.

## What you can rely on

- Full-disk encryption keyed to the lock screen (Android / OEM / Lineage baseline)
- WraithLink messenger: E2EE P2P over Tor, ephemeral messages, no message server
- Optional secondary **WraithVault** user for separating sensitive apps
- Soft panic: Setup can trigger `DevicePolicyManager.wipeData` after you enable the
  device admin — **software factory reset**, interruptible by a local attacker

## What you must not assume

| GrapheneOS WraithLink (Pixel) | WraithLink Lineage |
|---|---|
| Relock bootloader to *your* AVB key | Almost always stays unlocked |
| Titan/SE key-destroying duress | Not available — soft wipe only |
| GrapheneOS exploit mitigations baseline | Lineage + OEM kernel (device-dependent) |
| Sandboxed Play model | Not included; use F-Droid / your own gapps choice |
| Decoy PIN (vault wipe on unlock) | Not in Lineage v1 |

If an adversary images storage before unlock, or controls an unlocked bootloader,
software features on this edition do not undo that. Prefer **Pixel WraithLink** when
that threat model matters.

## Messenger vs OS

The messenger’s threat model (no server, Tor transport, verification) is the same APK
on both editions. That does **not** make the Lineage OS install as trustworthy as a
relocked GrapheneOS Pixel.
