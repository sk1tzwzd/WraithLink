#!/usr/bin/env bash
# WraithLink build-status dashboard.
# Usage:
#   bash scripts/wl-status.sh           # one-shot snapshot
#   bash scripts/wl-status.sh --watch   # live, refreshes every WL_STATUS_INTERVAL secs
# Override target with:  WL_SRV=builder@host bash scripts/wl-status.sh
set -uo pipefail

WL_SRV="${WL_SRV:-builder@169.58.128.67}"
INTERVAL="${WL_STATUS_INTERVAL:-10}"

C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_GRN=$'\033[1;32m'; C_YEL=$'\033[1;33m'
C_RED=$'\033[1;31m'; C_CYN=$'\033[1;36m'; C_MAG=$'\033[1;35m'; C_GRY=$'\033[0;37m'

banner() {
  printf '%s' "$C_MAG"
  cat <<'ART'
 __      __              _  _    _      _         _
 \ \    / /             (_)| |  | |    (_)       | |
  \ \  / /_ __  __ _  _  _ | |_ | |__   _  _ __  | | __
   \ \/ /| '__|/ _` || || || __|| '_ \ | || '_ \ | |/ /
    \  / | |  | (_| || || || |_ | | | || || | | ||   <
     \/  |_|   \__,_||_||_| \__||_| |_||_||_| |_||_|\_\
ART
  printf '%s' "$C_RESET"
}

# Remote collector: prints structured KEY=VALUE lines + an ACTIVITY block.
REMOTE='
src=$HOME/wraithlink-src
repo=$HOME/wraithlink
kv(){ printf "%s=%s\n" "$1" "$2"; }

# --- sync ---
if grep -q "repo sync has finished successfully" "$HOME/sync.log" 2>/dev/null; then kv SYNC done
elif pgrep -f "main.py.*sync" >/dev/null 2>&1; then kv SYNC running
else kv SYNC pending; fi

# --- vendor ---
if grep -q "Vendor files ready" "$HOME/vendor.log" 2>/dev/null; then kv VENDOR done
elif grep -q "\[ fail \]" "$HOME/vendor.log" 2>/dev/null; then kv VENDOR failed
elif pgrep -f "bin/run generate-all" >/dev/null 2>&1; then kv VENDOR running
else kv VENDOR pending; fi

# --- keys ---
if ls "$repo"/keys/*/releasekey.pk8 >/dev/null 2>&1 || ls "$HOME/.android-certs"/releasekey.pk8 >/dev/null 2>&1; then kv KEYS done
else kv KEYS pending; fi

# --- rebrand ---
if [ -f "$src/.wraithlink-rebranded" ]; then kv REBRAND done; else kv REBRAND pending; fi

# --- build --- (gate on our build.log so adevtool internal ninja does not false-positive)
if ls "$src"/out/target/product/*/*-ota_update-*.zip >/dev/null 2>&1; then kv BUILD done
elif [ -f "$HOME/build.log" ] && pgrep -f "soong_ui" >/dev/null 2>&1; then kv BUILD running
else kv BUILD pending; fi

# --- host vitals ---
kv DISK "$(df -h / | awk "NR==2{print \$3\" used / \"\$4\" free\"}")"
kv MEM "$(free -h | awk "/Mem:/{print \$3\" used / \"\$2\" total\"}")"
kv SWAP "$(free -h | awk "/Swap:/{print \$3\" used / \"\$2\" total\"}")"
kv LOAD "$(uptime | sed "s/.*load average: //")"
kv CPU "$(nproc) cores"

# --- active log tail (whichever log is freshest) ---
latest=$(ls -t "$HOME"/sync.log "$HOME"/vendor.log "$HOME"/keys.log "$HOME"/build.log 2>/dev/null | head -1)
echo "ACTIVITY_FILE=${latest##*/}"
# live percentage from the freshest log (adevtool "[ 76% .. ]", downloads "76%", ninja "[ 45% ..]")
pct=$([ -n "$latest" ] && tail -40 "$latest" 2>/dev/null | tr "\r" "\n" | grep -oE "[0-9]{1,3}%" | tail -1 | tr -d "%")
echo "PCT=${pct:-}"
echo "===ACTIVITY==="
[ -n "$latest" ] && tail -4 "$latest" | tr "\r" "\n" | tail -4
'

status_icon() {
  case "$1" in
    done)    printf '%s[ done ]%s' "$C_GRN" "$C_RESET" ;;
    running) printf '%s[ .... ]%s' "$C_YEL" "$C_RESET" ;;
    failed)  printf '%s[ FAIL ]%s' "$C_RED" "$C_RESET" ;;
    *)       printf '%s[ wait ]%s' "$C_DIM" "$C_RESET" ;;
  esac
}

# progress_bar <label> <pct 0-100>  ->  label [########..........]  62%
progress_bar() {
  local label="$1" pct="${2:-0}" width=34 i filled bar="" rest=""
  [ -z "$pct" ] && pct=0
  [ "$pct" -gt 100 ] && pct=100
  filled=$(( pct * width / 100 ))
  for ((i=0;i<filled;i++)); do bar+="#"; done
  for ((i=filled;i<width;i++)); do rest+="."; done
  printf '  %s%-16s%s [%s%s%s%s%s] %s%3s%%%s\n' \
    "$C_CYN" "$label" "$C_RESET" \
    "$C_GRN" "$bar" "$C_DIM" "$rest" "$C_RESET" \
    "$C_YEL" "$pct" "$C_RESET"
}

render() {
  local data; data="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$WL_SRV" "$REMOTE" 2>/dev/null)"
  if [ -z "$data" ]; then
    printf '%s  ! cannot reach %s%s\n' "$C_RED" "$WL_SRV" "$C_RESET"; return 1
  fi
  local sync vendor keys rebrand build disk mem swap load cpu actfile
  sync=$(sed -n 's/^SYNC=//p'      <<<"$data")
  vendor=$(sed -n 's/^VENDOR=//p'  <<<"$data")
  keys=$(sed -n 's/^KEYS=//p'      <<<"$data")
  rebrand=$(sed -n 's/^REBRAND=//p'<<<"$data")
  build=$(sed -n 's/^BUILD=//p'    <<<"$data")
  disk=$(sed -n 's/^DISK=//p'      <<<"$data")
  mem=$(sed -n 's/^MEM=//p'        <<<"$data")
  swap=$(sed -n 's/^SWAP=//p'      <<<"$data")
  load=$(sed -n 's/^LOAD=//p'      <<<"$data")
  cpu=$(sed -n 's/^CPU=//p'        <<<"$data")
  actfile=$(sed -n 's/^ACTIVITY_FILE=//p' <<<"$data")
  local pct stage done_ct overall
  pct=$(sed -n 's/^PCT=//p' <<<"$data")
  stage="idle"
  if   [ "$sync" = running ];   then stage="source sync"
  elif [ "$vendor" = running ]; then stage="vendor extract"
  elif [ "$keys" = running ];   then stage="signing keys"
  elif [ "$build" = running ];  then stage="os build"; fi
  done_ct=0
  for s in "$sync" "$vendor" "$keys" "$rebrand" "$build"; do [ "$s" = done ] && done_ct=$((done_ct+1)); done
  overall=$(( done_ct * 20 ))
  [ "$stage" != idle ] && [ -n "$pct" ] && overall=$(( overall + pct * 20 / 100 ))

  printf '  %sroot@wraithlink%s:%s~%s# build-status   %s%s%s\n\n' \
    "$C_GRN" "$C_RESET" "$C_CYN" "$C_RESET" "$C_DIM" "$(date '+%H:%M:%S')" "$C_RESET"
  printf '   1. source sync .......... %s\n' "$(status_icon "$sync")"
  printf '   2. vendor extract ....... %s\n' "$(status_icon "$vendor")"
  printf '   3. signing keys ......... %s\n' "$(status_icon "$keys")"
  printf '   4. rebrand + overlays ... %s\n' "$(status_icon "$rebrand")"
  printf '   5. os build ............. %s\n' "$(status_icon "$build")"
  printf '\n'
  progress_bar "overall" "$overall"
  [ "$stage" != idle ] && progress_bar "> ${stage}" "${pct:-0}"
  printf '\n  %sdisk%s %s   %scpu%s %s\n' "$C_GRY" "$C_RESET" "$disk" "$C_GRY" "$C_RESET" "${cpu:-?}"
  printf '  %smem%s  %s   %sswap%s %s\n'  "$C_GRY" "$C_RESET" "$mem"  "$C_GRY" "$C_RESET" "$swap"
  printf '  %sload%s %s\n' "$C_GRY" "$C_RESET" "$load"
  printf '\n  %s--- live: %s ---%s\n' "$C_CYN" "${actfile:-none}" "$C_RESET"
  sed -n '/^===ACTIVITY===$/,$p' <<<"$data" | tail -n +2 | sed "s/^/  ${C_DIM}| ${C_RESET}/"
}

if [ "${1:-}" = "--watch" ]; then
  trap 'printf "\n%sbye.%s\n" "$C_RESET" "$C_RESET"; exit 0' INT
  while true; do
    clear; banner; echo; render
    printf '\n  %srefreshing every %ss - Ctrl-C to quit%s\n' "$C_DIM" "$INTERVAL" "$C_RESET"
    sleep "$INTERVAL"
  done
else
  banner; echo; render
fi
