#!/usr/bin/env bash
# Shared helpers for WraithLink Lineage scripts.
set -euo pipefail

_wl_c() { printf '\033[%sm' "$1"; }
log()  { printf '%s[WL-Lineage]%s %s\n' "$(_wl_c '1;36')" "$(_wl_c 0)" "$*"; }
ok()   { printf '%s[  ok  ]%s %s\n'     "$(_wl_c '1;32')" "$(_wl_c 0)" "$*"; }
warn() { printf '%s[ warn ]%s %s\n'     "$(_wl_c '1;33')" "$(_wl_c 0)" "$*" >&2; }
die()  { printf '%s[ fail ]%s %s\n'     "$(_wl_c '1;31')" "$(_wl_c 0)" "$*" >&2; exit 1; }

WL_LINEAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WL_REPO_ROOT="$(cd "${WL_LINEAGE_ROOT}/.." && pwd)"

load_lineage_config() {
  local cfg="${WL_CONFIG:-${WL_LINEAGE_ROOT}/config/wraithlink-lineage.conf}"
  [ -f "$cfg" ] || die "Missing config: $cfg (copy from config/wraithlink-lineage.conf.example)"
  # shellcheck disable=SC1090
  source "$cfg"
  : "${WL_SRC_DIR:?}"
  : "${WL_LINEAGE_BRANCH:?}"
  : "${WL_MANIFEST_URL:?}"
}

# Messenger: https://github.com/sk1tzwzd/WraithLink-Messenger
resolve_chat_src() {
  local cand
  if [ -n "${WL_CHAT_SRC:-}" ]; then
    cand="$(cd "$WL_CHAT_SRC" 2>/dev/null && pwd)" || die "WL_CHAT_SRC not a directory: ${WL_CHAT_SRC}"
    [ -x "${cand}/gradlew" ] || die "WL_CHAT_SRC missing gradlew: ${cand}"
    printf '%s\n' "$cand"
    return 0
  fi
  for cand in \
    "${WL_REPO_ROOT}/../WraithLink-Messenger" \
    "${HOME}/Projects/WraithLink-Messenger" \
    "${HOME}/WraithLink-Messenger"
  do
    if [ -x "${cand}/gradlew" ]; then
      (cd "$cand" && pwd)
      return 0
    fi
  done
  die "WraithLink-Messenger not found. Clone as sibling or set WL_CHAT_SRC."
}
