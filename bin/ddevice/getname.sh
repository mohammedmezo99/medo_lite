#!/bin/bash
work_dir=$(pwd)
source "$work_dir/functions.sh"

FILE_JSON1="$work_dir/bin/ddevice/data/devices.json"
FILE_JSON2="$work_dir/bin/ddevice/data/names.json"

PYTHON_BIN="python3"
if ! command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python"
fi

read_clean() {
  local file="$1"
  [ -f "$file" ] || return 0
  cat "$file" 2>/dev/null | tr -d '\000\377\376\r\n'
}

KEY="$(read_clean "$work_dir/bin/ddevice/device_f.txt")"
CODE="$(read_clean "$work_dir/bin/ddevice/device_code.txt")"

is_bad_value() {
  local value="$1"
  [[ -z "$value" || "$value" == "null" || "$value" == *"Not found"* ]]
}

lookup_json_case_insensitive() {
  local json_file="$1"
  local lookup_key="$2"

  [ -f "$json_file" ] || return 0
  [ -n "$lookup_key" ] || return 0

  "$PYTHON_BIN" - "$json_file" "$lookup_key" << 'PY' 2>/dev/null
import json
import sys

json_file = sys.argv[1]
lookup_key = sys.argv[2].strip().lower()

try:
    with open(json_file, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

for key, value in data.items():
    if str(key).strip().lower() == lookup_key:
        print(value)
        break
PY
}

VALUE=""

CANDIDATES=(
  "$KEY"
  "$CODE"
  "$(echo "$KEY" | tr '[:lower:]' '[:upper:]')"
  "$(echo "$CODE" | tr '[:lower:]' '[:upper:]')"
)

for candidate in "${CANDIDATES[@]}"; do
  [ -n "$candidate" ] || continue

  for json_file in "$FILE_JSON1" "$FILE_JSON2"; do
    result="$(lookup_json_case_insensitive "$json_file" "$candidate")"
    if ! is_bad_value "$result"; then
      VALUE="$result"
      break 2
    fi
  done
done

if is_bad_value "$VALUE"; then
  while IFS= read -r prop_file; do
    [ -f "$prop_file" ] || continue

    for prop_key in \
      ro.product.marketname \
      ro.product.system.marketname \
      ro.product.vendor.marketname \
      ro.product.product.marketname \
      ro.product.odm.marketname \
      ro.product.model \
      ro.product.system.model \
      ro.product.vendor.model \
      ro.product.product.model
    do
      result="$(grep -h -m1 "^${prop_key}=" "$prop_file" 2>/dev/null | cut -d '=' -f 2- | tr -d '\r')"
      if ! is_bad_value "$result"; then
        VALUE="$result"
        break 2
      fi
    done
  done < <(find "$work_dir/build/baserom/images" -type f -name "build.prop" 2>/dev/null)
fi

if is_bad_value "$VALUE"; then
  if [ -n "$KEY" ]; then
    VALUE="Xiaomi ${KEY^^}"
  elif [ -n "$CODE" ]; then
    VALUE="Xiaomi ${CODE^^}"
  else
    VALUE="Unknown Xiaomi Device"
  fi
  warn "Device name not found in database. Using fallback: $VALUE"
fi

printf '%s\n' "$VALUE" > "$work_dir/bin/ddevice/name_devices.txt"
printf '%s\n' "$VALUE" > "$work_dir/bin/ddevice/device_name.txt"
printf '%s\n' "$KEY" > "$work_dir/bin/ddevice/codename.txt"

info "Device Name: $VALUE"