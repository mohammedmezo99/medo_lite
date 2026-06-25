#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ -f "$work_dir/functions.sh" ]]; then
    # shellcheck disable=SC1091
    source "$work_dir/functions.sh"
fi

mod_log() {
    if declare -F mods >/dev/null 2>&1; then
        mods "[POCO Launcher Spoof] $1"
    else
        echo "[POCO Launcher Spoof] $1"
    fi
}

mod_warn() {
    if declare -F warn >/dev/null 2>&1; then
        warn "[POCO Launcher Spoof] $1"
    else
        echo "[POCO Launcher Spoof][WARN] $1"
    fi
}

SCRIPT="$SCRIPT_DIR/poco_launcher_spoof.py"
BASE="$work_dir/build/baserom/images"

if [[ ! -f "$SCRIPT" ]]; then
    mod_warn "Missing script: $SCRIPT"
    exit 0
fi

if [[ ! -d "$BASE" ]]; then
    mod_warn "ROM images folder not found: $BASE"
    exit 0
fi

# POCO guard:
# 1) Prefer exact vendor brand property.
# 2) Fallback to parsed device metadata if available.
is_poco=false

if grep -RIsq '^ro\.product\.vendor\.brand=POCO$' \
    "$BASE/vendor" \
    "$BASE/vendor/vendor" \
    "$BASE/odm" \
    "$BASE/odm/odm" \
    "$BASE/odm/etc" 2>/dev/null; then
    is_poco=true
elif grep -RIsi 'poco' "$work_dir/bin/ddevice" 2>/dev/null | grep -qi 'poco'; then
    is_poco=true
fi

if [[ "$is_poco" != "true" ]]; then
    mod_log "Skip: POCO device was not detected."
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    mod_warn "python3 not found; skipping."
    exit 0
fi

mod_log "POCO device detected. Running launcher spoof..."
python3 "$SCRIPT" --work-dir "$work_dir" --style lite
mod_log "POCO launcher spoof finished."
