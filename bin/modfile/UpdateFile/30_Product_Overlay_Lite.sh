#!/usr/bin/env bash
set -euo pipefail

work_dir="$(pwd)"
source "$work_dir/functions.sh" 2>/dev/null || true

if declare -F mods >/dev/null; then
  mods "Starting Product Overlay Lite mod..."
else
  echo "[MODS] - Starting Product Overlay Lite mod..."
fi

SRC_DIR="$work_dir/bin/modfile/UpdateFile/Lite/Product_Overlay/overlay"
PRODUCT_DIR="$work_dir/build/baserom/images/product"
DEST_DIR="$PRODUCT_DIR/overlay"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "[Overlay Lite] Source folder not found: $SRC_DIR"
  exit 0
fi

if [[ ! -d "$PRODUCT_DIR" ]]; then
  echo "[Overlay Lite] Product partition not found: $PRODUCT_DIR"
  exit 0
fi

mkdir -p "$DEST_DIR"

shopt -s dotglob nullglob
items=("$SRC_DIR"/*)

if (( ${#items[@]} == 0 )); then
  echo "[Overlay Lite] Source overlay folder is empty. Skip."
  exit 0
fi

cp -a "${items[@]}" "$DEST_DIR/"

echo "[Overlay Lite] Copied overlay files into: $DEST_DIR"
echo "[Overlay Lite] Existing product/overlay content was preserved."
