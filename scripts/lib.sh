#!/usr/bin/env bash
# Shared helpers + config loader for WraithLink build scripts.
# Source this at the top of every script:  . "$(dirname "$0")/lib.sh"

set -euo pipefail

WL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- pretty logging ---
_wl_c() { printf '\033[%sm' "$1"; }
log()  { printf '%s[WraithLink]%s %s\n' "$(_wl_c '1;36')" "$(_wl_c 0)" "$*"; }
ok()   { printf '%s[  ok  ]%s %s\n'     "$(_wl_c '1;32')" "$(_wl_c 0)" "$*"; }
warn() { printf '%s[ warn ]%s %s\n'     "$(_wl_c '1;33')" "$(_wl_c 0)" "$*" >&2; }
die()  { printf '%s[ fail ]%s %s\n'     "$(_wl_c '1;31')" "$(_wl_c 0)" "$*" >&2; exit 1; }

# --- config ---
# Override with WL_CONFIG=/path/to/wraithlink-akita.conf for multi-device builds.
load_config() {
  local cfg="${WL_CONFIG:-${WL_ROOT}/config/wraithlink.conf}"
  [ -f "$cfg" ] || die "Missing config: $cfg  (copy from config/wraithlink.conf.example and edit)"
  # shellcheck disable=SC1090
  . "$cfg"
  : "${WL_DEVICE:?WL_DEVICE not set}"
  : "${WL_SRC_DIR:?WL_SRC_DIR not set}"
  : "${WL_BRANCH:?WL_BRANCH not set}"
  # Re-derive keys dir if conf uses ${WL_DEVICE} expansion after overrides.
  : "${WL_KEYS_DIR:=${WL_SRC_DIR}/keys/${WL_DEVICE}}"
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1  (run scripts/00-setup-build-env.sh)"; }

# Messenger lives in a separate repo: https://github.com/sk1tzwzd/WraithLink-Messenger
# Resolve checkout via WL_CHAT_SRC or sibling ../WraithLink-Messenger.
resolve_chat_src() {
  local cand
  if [ -n "${WL_CHAT_SRC:-}" ]; then
    cand="$(cd "$WL_CHAT_SRC" 2>/dev/null && pwd)" || die "WL_CHAT_SRC not a directory: ${WL_CHAT_SRC}"
    [ -x "${cand}/gradlew" ] || die "WL_CHAT_SRC missing gradlew: ${cand}"
    printf '%s\n' "$cand"
    return 0
  fi
  for cand in \
    "${WL_ROOT}/../WraithLink-Messenger" \
    "${HOME}/Projects/WraithLink-Messenger" \
    "${HOME}/WraithLink-Messenger"
  do
    if [ -x "${cand}/gradlew" ]; then
      (cd "$cand" && pwd)
      return 0
    fi
  done
  die "WraithLink-Messenger not found. Clone https://github.com/sk1tzwzd/WraithLink-Messenger as a sibling, or set WL_CHAT_SRC."
}

# Refuse to run heavyweight steps on machines that clearly can't build AOSP.
preflight_build_host() {
  local mem_gib free_gib
  mem_gib=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  free_gib=$(df -BG --output=avail "$1" 2>/dev/null | tail -1 | tr -dc '0-9')
  [ "${mem_gib:-0}" -ge 32 ] || warn "Only ${mem_gib}GiB RAM detected; AOSP needs 32GiB+ (LTO/CFI will OOM below this)."
  [ "${free_gib:-0}" -ge 250 ] || warn "Only ${free_gib}GiB free at $1; need ~136GiB source + ~100GiB build."
}
