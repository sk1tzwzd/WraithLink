#!/usr/bin/env bash
# Build messenger APK into distribution/site/lineage/downloads/ (no Lineage tree required).
. "$(dirname "$0")/lib.sh"

CHAT_ROOT="$(resolve_chat_src)"
# Primary public download path on the main site; Lineage mirror kept in sync.
OUT_DIR="${WL_REPO_ROOT}/distribution/site/downloads"
LINEAGE_OUT_DIR="${WL_REPO_ROOT}/distribution/site/lineage/downloads"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${HOME}/android-sdk}"
export ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
if ! command -v java >/dev/null 2>&1; then
  for j in \
    "${HOME}/wraithlink-lineage-src/prebuilts/jdk/jdk21/linux-x86/bin" \
    "${HOME}/wraithlink-src/prebuilts/jdk/jdk21/linux-x86/bin"; do
    [ -x "${j}/java" ] && export PATH="${j}:${PATH}" && break
  done
fi
command -v java >/dev/null 2>&1 || die "java not found (install openjdk-17-jdk or use AOSP prebuilt JDK)"
[ -d "${ANDROID_SDK_ROOT}/platforms/android-35" ] \
  || die "Android SDK 35 missing at ${ANDROID_SDK_ROOT} — run scripts/00-setup-build-env.sh"

mkdir -p "$OUT_DIR"
cat > "${CHAT_ROOT}/local.properties" <<EOF
sdk.dir=${ANDROID_SDK_ROOT}
EOF

log "assembleRelease (${CHAT_ROOT})"
(cd "$CHAT_ROOT" && ./gradlew :app:assembleRelease --no-daemon)
CANDIDATE="$(ls -1 "${CHAT_ROOT}/app/build/outputs/apk/release/"*.apk 2>/dev/null | head -1 || true)"
[ -n "$CANDIDATE" ] || die "No release APK produced"

OUT="${OUT_DIR}/WraithLinkChat.apk"
KEYSTORE="${WL_CHAT_KEYSTORE:-}"
PASS="${WL_CHAT_KEY_PASSPHRASE:-${WL_KEY_PASSPHRASE:-}}"
if [ -n "$KEYSTORE" ] && [ -f "$KEYSTORE" ] && [ -n "$PASS" ]; then
  APKSIGNER="$(command -v apksigner || true)"
  [ -n "$APKSIGNER" ] || APKSIGNER="$(ls "${ANDROID_SDK_ROOT}"/build-tools/*/apksigner 2>/dev/null | tail -1 || true)"
  [ -n "$APKSIGNER" ] || die "apksigner not found"
  rm -f "$OUT"
  "$APKSIGNER" sign --ks "$KEYSTORE" --ks-key-alias wraithlink-chat \
    --ks-pass "pass:${PASS}" --key-pass "pass:${PASS}" --out "$OUT" "$CANDIDATE"
  "$APKSIGNER" verify "$OUT"
  ok "Signed ${OUT}"
else
  cp -f "$CANDIDATE" "$OUT"
  warn "Staged unsigned APK (set WL_CHAT_KEYSTORE + passphrase for release signing)"
fi

sha256sum "$OUT" | tee "${OUT}.sha256"
mkdir -p "$LINEAGE_OUT_DIR"
cp -f "$OUT" "${OUT}.sha256" "$LINEAGE_OUT_DIR/"
ok "Messenger APK ready at downloads/ and lineage/downloads/"
