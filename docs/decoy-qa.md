# Decoy-duress operator runbook (Milestone 2)

Dedicated rebuild + hardware QA. Do **not** flip `WL_ENABLE_DECOY_DURESS` on the lean v1 config used for published installer images until this checklist passes on hardware.

## Build (host)

```bash
export WL_CONFIG=/home/builder/wraithlink/config/wraithlink-decoy.conf
# conf must set: WL_DEVICE=tokay (or akita), WL_ENABLE_DECOY_DURESS=true
bash scripts/04-apply-rebrand.sh
# Confirm patch + prop fragment:
test -f "$WL_SRC_DIR/vendor/wraithlink/wraithlink-decoy.mk"
grep -q 'ro.wraithlink.decoy=1' "$WL_SRC_DIR/vendor/wraithlink/wraithlink-decoy.mk"
grep -q 'wraithlink-decoy.mk' "$WL_SRC_DIR/vendor/wraithlink/wraithlink.mk"
bash scripts/05-build.sh
bash scripts/06-generate-release.sh YYYYMMDDNN   # password=… for decrypt-keys
# Do NOT run 07-deploy-site.sh until hardware QA passes (keeps lean v1 on the installer).
```

Host preflight script (after target-files exist):

```bash
bash scripts/decoy-preflight.sh
```

## Device steps

Follow the checkbox list in [`docs/duress.md`](duress.md) § Hardware QA checklist.

Minimum happy path:

1. Flash decoy factory image; relock.
2. Setup: owner PIN → panic password → create vault → populate a marker file in vault → backup ack → set decoy PIN.
3. Lock; enter **owner** PIN → vault still listed.
4. Lock; enter **decoy** PIN → owner UI; vault gone; marker unrecoverable.
5. After re-setup of a throwaway device (or fresh flash): confirm **panic** still full-wipes.

## Publish rule

Only after hardware QA: deploy the decoy-signed release and update site copy from “Milestone 2 / not in lean image” to “available in build NNNN (`ro.wraithlink.decoy=1`)”.
