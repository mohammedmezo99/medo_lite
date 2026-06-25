#!/bin/bash
work_dir=$(pwd)
source "$work_dir/functions.sh"

ARG_KEY="${1:-}"

PYTHON_BIN="python3"
if ! command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python"
fi

"$PYTHON_BIN" "$work_dir/bin/ddevice/resolve_device.py" "$ARG_KEY"

VALUE="$(cat "$work_dir/bin/ddevice/device_name.txt" 2>/dev/null | tr -d '\r\n')"
if [ -z "$VALUE" ]; then
  VALUE="Unknown Xiaomi Device"
  printf '%s\n' "$VALUE" > "$work_dir/bin/ddevice/name_devices.txt"
  printf '%s\n' "$VALUE" > "$work_dir/bin/ddevice/device_name.txt"
fi

info "Device Name: $VALUE"