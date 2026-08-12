# Offline signing-key backup (do this before first publish)

WraithLink's verified boot and OTA trust root live in per-device key directories.
If these are lost, you cannot sign updates for existing installs. If they leak,
anyone can produce a trusted-looking image.

## What to back up

For each device you ship (`tokay`, `akita`, …):

| Path | Contents |
|---|---|
| `$WL_SRC_DIR/keys/<device>/` | Encrypted APK/AVB keys, `avb_pkmd.bin`, factory SSH key, chat keystore |
| Passphrase | The `WL_KEY_PASSPHRASE` / `password` used with `script/encrypt-keys` / `decrypt-keys` |
| Chat keystore pass | `WL_CHAT_KEY_PASSPHRASE` if different from the OS key passphrase |

## How

1. Copy each `keys/<device>/` directory to an encrypted USB drive or offline machine.
2. Store the passphrase separately (password manager offline export, or paper in a safe).
3. Verify you can decrypt on a second machine before wiping any build host.
4. Do **not** commit keys or passphrases to git, or leave them only on the build server.

## After backup

Proceed with `scripts/06-generate-release.sh` and `scripts/07-deploy-site.sh`.
