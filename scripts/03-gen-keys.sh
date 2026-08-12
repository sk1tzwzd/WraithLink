#!/usr/bin/env bash
# Phase 1: generate + encrypt WraithLink's own signing keys and AVB key.
# These become WraithLink's root of trust. BACK THEM UP OFFLINE.
# Reference: https://grapheneos.org/build#generating-release-signing-keys
. "$(dirname "$0")/lib.sh"
load_config

cd "$WL_SRC_DIR" || die "Source not found at ${WL_SRC_DIR} - run 01-sync-source.sh first."

if [ -d "$WL_KEYS_DIR" ] && [ -n "$(ls -A "$WL_KEYS_DIR" 2>/dev/null)" ]; then
  die "Keys already exist at ${WL_KEYS_DIR}. Refusing to overwrite (would break all prior installs). Move them aside to regenerate."
fi

mkdir -p "$WL_KEYS_DIR"
CN="$WL_CERT_CN"

log "Generating APK/verified-boot signing keys for ${WL_DEVICE} (CN=${CN})..."
( cd "$WL_KEYS_DIR"
  # Keys are created WITHOUT a per-key password; encrypt-keys (below) encrypts
  # them all at rest behind one passphrase. </dev/null makes make_key's password
  # prompt read EOF -> blank, so this runs non-interactively.
  for k in releasekey platform shared media networkstack bluetooth sdk_sandbox gmscompat_lib nfc; do
    "${WL_SRC_DIR}/development/tools/make_key" "$k" "/CN=${CN}/" </dev/null || true
  done

  # AVB key is generated UNENCRYPTED here; encrypt-keys re-encrypts it with the
  # same passphrase as the rest. (Generating it with -scrypt would double-encrypt
  # and break encrypt-keys, which expects an unencrypted avb.pem.)
  log "Generating AVB (verified boot) key..."
  openssl genrsa 4096 | openssl pkcs8 -topk8 -nocrypt -out avb.pem
  "${WL_SRC_DIR}/external/avb/avbtool.py" extract_public_key --key avb.pem --output avb_pkmd.bin

  log "Generating OpenSSH key for signing factory images..."
  ssh-keygen -t ed25519 -f id_ed25519 -N "" -C "wraithlink-${WL_DEVICE}"
)

log "Encrypting keys at rest..."
if [ -n "${WL_KEY_PASSPHRASE:-}" ]; then
  # Non-interactive: encrypt-keys prompts for old passphrase (empty, keys are
  # fresh), then the new passphrase twice.
  printf '\n%s\n%s\n' "$WL_KEY_PASSPHRASE" "$WL_KEY_PASSPHRASE" \
    | "${WL_SRC_DIR}/script/encrypt-keys" "$WL_KEYS_DIR" \
    || warn "encrypt-keys failed; keys remain UNENCRYPTED at ${WL_KEYS_DIR}."
else
  log "(interactive: press Enter for the old passphrase, then type your new passphrase twice)"
  "${WL_SRC_DIR}/script/encrypt-keys" "$WL_KEYS_DIR" \
    || warn "encrypt-keys not run/failed; keys remain UNENCRYPTED at ${WL_KEYS_DIR}."
fi

# Dedicated signing key for the WraithLink Messenger APK. Independent of the
# platform key so the app stays a normal removable system app (rotatable without
# reflashing the OS).
CHAT_JKS="${WL_KEYS_DIR}/wraithlink-chat.jks"
if [ ! -f "$CHAT_JKS" ]; then
  log "Generating dedicated WraithLink Messenger app keystore..."
  CHAT_PASS="${WL_CHAT_KEY_PASSPHRASE:-${WL_KEY_PASSPHRASE:-}}"
  if [ -z "$CHAT_PASS" ]; then
    CHAT_PASS="$(openssl rand -base64 24)"
    warn "Generated WL_CHAT_KEY_PASSPHRASE (save this): ${CHAT_PASS}"
    warn "Export it before build-and-stage: export WL_CHAT_KEY_PASSPHRASE='…'"
  fi
  keytool -genkeypair -v \
    -keystore "$CHAT_JKS" \
    -alias wraithlink-chat \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -storepass "$CHAT_PASS" -keypass "$CHAT_PASS" \
    -dname "CN=${CN} Chat, O=${CN}, C=US"
  ok "Messenger keystore: ${CHAT_JKS}"
else
  ok "Messenger keystore already present: ${CHAT_JKS}"
fi

warn "BACK UP ${WL_KEYS_DIR} OFFLINE NOW. If lost, you cannot sign updates; if leaked, WraithLink's trust is compromised."
ok "Signing identity ready. avb_pkmd.bin is used to lock the bootloader to WraithLink. Next: scripts/04-apply-rebrand.sh"
