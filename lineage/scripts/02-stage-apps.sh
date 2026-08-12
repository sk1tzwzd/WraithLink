#!/usr/bin/env bash
# Stage messenger + Lineage Setup + optional F-Droid into the Lineage source tree.
. "$(dirname "$0")/lib.sh"
load_lineage_config

SRC="$WL_SRC_DIR"
[ -d "$SRC" ] || die "Source missing: $SRC — run 01-sync.sh first"

VDIR="${SRC}/vendor/wraithlink-lineage"
log "Installing vendor overlay -> ${VDIR}"
mkdir -p "$VDIR"
rsync -a --delete \
  --exclude 'prebuilt-apps/*.apk' \
  "${WL_LINEAGE_ROOT}/vendor-overlay/" "$VDIR/"

# ---- Setup (in-tree platform app) ----
DEST="${SRC}/packages/apps/WraithLinkSetup"
log "Staging Lineage Setup -> ${DEST}"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "${WL_LINEAGE_ROOT}/apps/setup/Android.bp" \
      "${WL_LINEAGE_ROOT}/apps/setup/AndroidManifest.xml" \
      "${WL_LINEAGE_ROOT}/apps/setup/res" \
      "${WL_LINEAGE_ROOT}/apps/setup/src" \
      "$DEST/"
ok "WraithLinkSetup staged"

# ---- Messenger APK (Gradle) ----
PREBUILT="${VDIR}/prebuilt-apps"
mkdir -p "$PREBUILT"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${HOME}/android-sdk}"
export ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
# Prefer system JDK; fall back to Lineage/AOSP prebuilt JDK 21.
if ! command -v java >/dev/null 2>&1; then
  for j in \
    "${WL_SRC_DIR}/prebuilts/jdk/jdk21/linux-x86/bin" \
    "${HOME}/wraithlink-src/prebuilts/jdk/jdk21/linux-x86/bin"; do
    if [ -x "${j}/java" ]; then
      export PATH="${j}:${PATH}"
      break
    fi
  done
fi

OUT_APK="${PREBUILT}/WraithLinkChat.apk"
DIST_APK_DIR="${WL_REPO_ROOT}/distribution/site/downloads"
DIST_APK_LINEAGE="${WL_REPO_ROOT}/distribution/site/lineage/downloads"
mkdir -p "$DIST_APK_DIR" "$DIST_APK_LINEAGE"
CANDIDATE=""
CHAT_ROOT=""
if CHAT_ROOT="$(resolve_chat_src 2>/dev/null)"; then
  CANDIDATE="$(ls -1 "${CHAT_ROOT}/app/build/outputs/apk/release/"*.apk 2>/dev/null | head -1 || true)"
  if [ -z "$CANDIDATE" ]; then
    if [ ! -d "${ANDROID_SDK_ROOT}/platforms/android-35" ]; then
      warn "Android SDK 35 missing at ${ANDROID_SDK_ROOT} — run scripts/00-setup-build-env.sh (SDK section) first"
    fi
    log "Building WraithLink messenger from ${CHAT_ROOT}"
    cat > "${CHAT_ROOT}/local.properties" <<EOF
sdk.dir=${ANDROID_SDK_ROOT}
EOF
    (cd "$CHAT_ROOT" && ./gradlew :app:assembleRelease --no-daemon) || warn "Gradle chat build failed — ROM will lack messenger until fixed"
    CANDIDATE="$(ls -1 "${CHAT_ROOT}/app/build/outputs/apk/release/"*.apk 2>/dev/null | head -1 || true)"
  else
    ok "Reusing existing messenger APK: ${CANDIDATE}"
  fi
  if [ -n "$CANDIDATE" ]; then
    KEYSTORE="${WL_CHAT_KEYSTORE:-}"
    PASS="${WL_CHAT_KEY_PASSPHRASE:-${WL_KEY_PASSPHRASE:-}}"
    if [ -n "$KEYSTORE" ] && [ -f "$KEYSTORE" ] && [ -n "$PASS" ]; then
      APKSIGNER="$(command -v apksigner || true)"
      [ -n "$APKSIGNER" ] || APKSIGNER="$(ls "${ANDROID_SDK_ROOT}"/build-tools/*/apksigner 2>/dev/null | tail -1 || true)"
      if [ -n "$APKSIGNER" ]; then
        rm -f "$OUT_APK"
        "$APKSIGNER" sign --ks "$KEYSTORE" --ks-key-alias wraithlink-chat \
          --ks-pass "pass:${PASS}" --key-pass "pass:${PASS}" \
          --out "$OUT_APK" "$CANDIDATE"
        ok "Signed messenger -> ${OUT_APK}"
      else
        cp -f "$CANDIDATE" "$OUT_APK"
        warn "apksigner missing; staged unsigned chat APK"
      fi
    else
      cp -f "$CANDIDATE" "$OUT_APK"
      warn "No chat keystore/passphrase; staged unsigned chat APK (set WL_CHAT_KEYSTORE)"
    fi
    cp -f "$OUT_APK" "${DIST_APK_DIR}/WraithLinkChat.apk"
    sha256sum "$OUT_APK" | tee "${DIST_APK_DIR}/WraithLinkChat.apk.sha256" >/dev/null
    cp -f "$OUT_APK" "${DIST_APK_DIR}/WraithLinkChat.apk.sha256" "$DIST_APK_LINEAGE/"
    bp="${PREBUILT}/Android.bp"
    if ! grep -q 'name: "WraithLink_Chat"' "$bp" 2>/dev/null; then
      cat >> "$bp" <<'EOF'

android_app_import {
    name: "WraithLink_Chat",
    apk: "WraithLinkChat.apk",
    presigned: true,
    preprocessed: true,
    dex_preopt: { enabled: false },
}
EOF
    fi
    touch "${VDIR}/wraithlink-apps.mk"
    if ! grep -q 'PRODUCT_PACKAGES += WraithLink_Chat' "${VDIR}/wraithlink-apps.mk" 2>/dev/null; then
      echo "PRODUCT_PACKAGES += WraithLink_Chat" >> "${VDIR}/wraithlink-apps.mk"
    fi
    ok "Messenger registered + copied to site downloads/"
  fi
else
  warn "WraithLink-Messenger not found (clone sibling or set WL_CHAT_SRC) — skip messenger stage"
fi

# ---- F-Droid (optional fetch) ----
FDROID_URL="${WL_FDROID_APK_URL:-https://f-droid.org/F-Droid.apk}"
FDROID_APK="${PREBUILT}/FDroid.apk"
if [ ! -f "$FDROID_APK" ]; then
  log "Fetching F-Droid APK"
  if curl -fsSL -o "$FDROID_APK" "$FDROID_URL"; then
    if ! grep -q 'name: "WraithLink_FDroid"' "${PREBUILT}/Android.bp" 2>/dev/null; then
      cat >> "${PREBUILT}/Android.bp" <<'EOF'

android_app_import {
    name: "WraithLink_FDroid",
    apk: "FDroid.apk",
    presigned: true,
    preprocessed: true,
    dex_preopt: { enabled: false },
}
EOF
    fi
    if ! grep -q 'PRODUCT_PACKAGES += WraithLink_FDroid' "${VDIR}/wraithlink-apps.mk" 2>/dev/null; then
      echo "PRODUCT_PACKAGES += WraithLink_FDroid" >> "${VDIR}/wraithlink-apps.mk"
    fi
    ok "F-Droid staged"
  else
    warn "F-Droid download failed — continue without it"
    rm -f "$FDROID_APK"
  fi
fi

ok "Staging complete. Inherit vendor/wraithlink-lineage/wraithlink.mk from device products (03-build-device.sh does this)."
