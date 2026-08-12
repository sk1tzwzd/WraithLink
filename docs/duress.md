# Duress credentials & WraithVault

WraithLink keeps **three separate ideas**. Do not conflate them.

| Credential | When to use | What happens |
|---|---|---|
| **Owner PIN/password** | Everyday unlock | Opens the owner profile. WraithVault untouched. |
| **Panic (GrapheneOS duress)** | You can burn the whole phone | Destroys disk-encryption keys first, then wipes. Entire device, including WraithVault. |
| **Decoy PIN** (M2, `ro.wraithlink.decoy=1`) | Coercion while someone watches the screen | Unlocks the **owner** profile normally; **silently destroys WraithVault** (and other non-system secondary users) in the background. |

The decoy PIN is **not** a replacement for panic wipe. Keep both armed when you use decoy builds.

## Panic wipe (always in the image)

Inherited from GrapheneOS, unchanged:

1. Deletes encryption keys (data becomes unrecoverable),
2. Wipes eSIM profiles (if configured),
3. Reboots into a factory-reset state.

Configure: Settings → Security → Duress password, or Setup → “Duress (panic) password”.

If a panic credential equals the owner credential, the owner credential wins (GrapheneOS rule — you cannot lock yourself out by coincidence).

## Decoy PIN (Milestone 2)

Gated by `WL_ENABLE_DECOY_DURESS=true`. When applied, the build advertises `ro.wraithlink.decoy=1` and Setup shows the decoy step.

Behavior (see `DecoyDuressHelper` / `WraithVaultDestroy`):

- Decoy PIN unwraps an escrow of the owner credential → unlock looks normal.
- Background thread calls `removeUserWhenPossible` on the vault user id and any other non-system secondary users.
- CE storage keys for those users are destroyed early in removal.

### Honest ceiling

- Defeats coercion / casual inspection of the unlocked UI.
- Does **not** defeat a lab that imaged storage before unlock.
- WraithVault is a **visible** secondary user; decoy is not “hidden vault” or forensic deniability.
- Collateral: **all** non-system secondary users are removed, not only WraithVault.

### Arming rules (Setup)

1. Create WraithVault.
2. Back it up off-phone (X47 or encrypted USB).
3. Tap **I’ve backed up** (writes `wraithlink_vault_backup_acked=1`). Setup **refuses** to set a decoy PIN until this ack exists.
4. Set decoy PIN (must differ from owner; digits only, ≥4).

## WraithVault

Secondary Android user created from Setup — not Private Space. Own lock, own apps. Not hidden from the profile switcher or forensics. Back it up before arming decoy or relying on panic wipe.

## Hardware QA checklist (decoy builds)

Run on a real Pixel after flashing a build with `ro.wraithlink.decoy=1`. Record pass/fail.

### Preflight (host / image)

- [ ] `getprop ro.wraithlink.decoy` → `1`
- [ ] Setup shows “Decoy-duress PIN” step
- [ ] Lean/published v1 image (without the prop) does **not** show that step

### Credentials

- [ ] Owner PIN unlocks; vault still present
- [ ] Panic credential full-wipes (keys destroyed); device factory-reset afterward
- [ ] Decoy PIN ≠ owner ≠ panic
- [ ] Setup blocks decoy set until “I’ve backed up” is tapped
- [ ] Setup blocks decoy set if vault was never created (expected fail path)

### Decoy unlock

- [ ] Entering decoy at lockscreen unlocks **owner** with no wipe UI / no factory-reset animation
- [ ] Within ~30s, WraithVault user is gone (Users / `pm list users`)
- [ ] Other non-system secondary users are also gone
- [ ] Owner apps/data on primary user still present
- [ ] Re-entering owner PIN still works after decoy was used once (re-arm / recreate vault as needed for further tests)

### Regression

- [ ] USB-while-locked, auto-reboot, media strip still behave as on lean image
- [ ] Verified boot / relock still OK after flash

See also [`docs/decoy-qa.md`](decoy-qa.md) for the operator runbook.
