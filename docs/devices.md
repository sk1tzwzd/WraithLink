# Supported devices

WraithLink is **Pixel-only**, inheriting GrapheneOS's device support. This is a hardware
requirement, not a preference.

## Why Pixel-only

- **Re-lockable bootloader with a custom key** — required for verified boot of a custom
  OS. Pixels support relocking against your own AVB key; nearly all other phones do not.
- **Secure element (Titan M2)** — StrongBox key storage and the real duress wipe.
- **Hardware attestation** — proves boot integrity to apps/services.
- **Memory tagging (MTE)** and other Tensor mitigations GrapheneOS depends on.
- **Buildable monthly firmware/driver updates** — published for Pixels, rarely elsewhere.

On non-Pixels you can install a custom OS but lose verified boot, attestation, and the
genuine duress guarantee — i.e. WraithLink's whole point.

## v1 ship targets

| Device | Codename | Notes |
|---|---|---|
| Pixel 9 | `tokay` | Reference build / factory images |
| Pixel 8a | `akita` | Second ship target |

Set `WL_DEVICE` in `config/wraithlink.conf` to the codename. Other GrapheneOS Pixels
(e.g. `caiman`, `shiba`) can use the same pipeline later; they are not part of the
first published installer set.

## Out of scope for v1

Non-Pixel "ported" devices (Fairphone, Sony, etc.) need per-device kernel/SELinux/firmware
work and are not planned for the first release.
