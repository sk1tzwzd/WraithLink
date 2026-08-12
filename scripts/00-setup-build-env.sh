#!/usr/bin/env bash
# Phase 0: install GrapheneOS/AOSP + Vanadium build dependencies on Debian 12.
# Reference: https://grapheneos.org/build
. "$(dirname "$0")/lib.sh"
load_config

[ "$(id -u)" -eq 0 ] && die "Do not run as root; the script uses sudo where needed."
require_cmd sudo

log "Detecting distro..."
. /etc/os-release
case "${ID}:${VERSION_CODENAME:-}" in
  debian:bookworm) ok "Debian 12 (bookworm) - officially supported." ;;
  ubuntu:*)        warn "Ubuntu detected; officially supported: 24.04/24.10. Proceeding." ;;
  arch:*)          warn "Arch detected; package names differ - install repo/yarn/zip/rsync manually." ; exit 0 ;;
  *)               warn "Unsupported distro '${ID}'. AOSP officially supports Debian 12 / Ubuntu 24.04 / Arch." ;;
esac

log "Installing core packages (apt)..."
sudo apt-get update
# Core repo/build deps + AOSP extras + Vanadium (Chromium) 32-bit deps.
# NOTE: Node/yarn are installed separately below - distro nodejs is too old for adevtool.
sudo apt-get install -y \
  repo zip unzip rsync git gnupg openssh-client \
  python3 diffutils fontconfig libfreetype6 hostname openssl \
  gperf ccache lib32z1 libc6-dev-i386 lib32gcc-s1 lib32stdc++6 \
  curl

# Ensure sbin dirs are on PATH (AOSP build sometimes needs them).
if ! grep -q '/usr/local/sbin' <<<"$PATH"; then
  echo 'export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin' >> "${HOME}/.bashrc"
  warn "Added /sbin dirs to PATH in ~/.bashrc - run 'source ~/.bashrc' or re-login."
fi

# adevtool's runtime requires Node >= 24 (Ubuntu 24.04 ships 18). Install Node 24
# from NodeSource, then yarn (classic) via npm.
NODE_MAJOR="$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 24 ]; then
  log "Installing Node.js 24 (adevtool requires >= 24; found: ${NODE_MAJOR:-none})..."
  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
if ! command -v yarn >/dev/null 2>&1; then
  log "Installing yarn (classic) via npm..."
  sudo npm install -g yarn
fi
ok "Node $(node -v) / yarn $(yarn --version) ready for adevtool."

# AOSP's Soong build uses nsjail sandboxing, which needs unprivileged user
# namespaces. Ubuntu 24.04 restricts these via AppArmor by default; that makes
# nsjail fail and adevtool abort on the resulting stderr warning. Allow them.
if [ -e /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]; then
  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null || true
  echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee /etc/sysctl.d/99-wraithlink-userns.conf >/dev/null
  ok "Enabled unprivileged user namespaces (needed for nsjail/soong)."
fi

# ---- Android app toolchain (for the WraithLink messenger APK) ----
# The messenger (WraithLink-Messenger sibling repo) is a Gradle/Compose app, so it
# needs a JDK, the Android SDK, and Gradle - none of which the AOSP build itself
# requires. Used by apps/chat/build-and-stage.sh via WL_CHAT_SRC.
log "Installing JDK 17 + Android SDK + Gradle for the WraithLink messenger app..."
sudo apt-get install -y openjdk-17-jdk

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${HOME}/android-sdk}"
CLT="${ANDROID_SDK_ROOT}/cmdline-tools/latest"
if [ ! -x "${CLT}/bin/sdkmanager" ]; then
  log "Installing Android command-line tools -> ${ANDROID_SDK_ROOT}"
  mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
  tmpd="$(mktemp -d)"
  curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
    -o "${tmpd}/clt.zip"
  unzip -q "${tmpd}/clt.zip" -d "${tmpd}"
  rm -rf "${CLT}"; mkdir -p "$(dirname "${CLT}")"
  mv "${tmpd}/cmdline-tools" "${CLT}"
  rm -rf "${tmpd}"
fi
export ANDROID_SDK_ROOT
export PATH="${CLT}/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" >/dev/null \
  && ok "Android SDK 35 + build-tools 35.0.0 installed." \
  || warn "sdkmanager install failed; re-run after checking network/licenses."

GRADLE_VER="8.10.2"
if ! command -v gradle >/dev/null 2>&1; then
  log "Installing Gradle ${GRADLE_VER}..."
  curl -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VER}-bin.zip" -o /tmp/gradle.zip
  sudo unzip -q -o /tmp/gradle.zip -d /opt
  sudo ln -sf "/opt/gradle-${GRADLE_VER}/bin/gradle" /usr/local/bin/gradle
  rm -f /tmp/gradle.zip
fi

# Persist SDK env so later phases (messenger stage scripts) find it.
if ! grep -q 'ANDROID_SDK_ROOT' "${HOME}/.bashrc" 2>/dev/null; then
  {
    echo "export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT}"
    echo "export PATH=\$PATH:${CLT}/bin:${ANDROID_SDK_ROOT}/platform-tools"
  } >> "${HOME}/.bashrc"
fi
ok "Android app toolchain ready (JDK 17, SDK 35, Gradle ${GRADLE_VER})."

ok "Build environment ready. Next: scripts/01-sync-source.sh"
