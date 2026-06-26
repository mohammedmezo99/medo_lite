#!/bin/bash
set -e

work_dir=$(pwd)
source "$work_dir/functions.sh"

rom_os=$(cat "$work_dir/bin/ddevice/rom_os.txt")
androidVER=$(cat "$work_dir/bin/ddevice/androidver.txt")
MAIN_FOLDER="$work_dir/build/baserom/images"

MOD_DIR="$work_dir/bin/modfile/OS1/thememanager"
TARGET_DIR="$MAIN_FOLDER/product/priv-app/MIUIThemeManager"
PERM_TARGET="$MAIN_FOLDER/product/etc/permissions"
PERM_FILE="$MOD_DIR/permissions/privapp_whitelist_com.android.thememanager.xml"

mods "OS1 ThemeManager"

if [[ "$rom_os" != "OS1" ]]; then
  warn "OS1 ThemeManager skipped: ROM is not OS1"
  exit 0
fi

case "$androidVER" in
  14)
    THEME_SRC="$MOD_DIR/MIUIThemeManager_14"
    ;;
  13)
    THEME_SRC="$MOD_DIR/MIUIThemeManager_13"
    ;;
  *)
    THEME_SRC="$MOD_DIR/MIUIThemeManager"
    warn "OS1 ThemeManager: unsupported Android $androidVER, using fallback source"
    ;;
esac

if [ ! -d "$THEME_SRC" ]; then
  warn "OS1 ThemeManager source not found: $THEME_SRC"
  warn "Trying fallback: $MOD_DIR/MIUIThemeManager"
  THEME_SRC="$MOD_DIR/MIUIThemeManager"
fi

if [ ! -d "$THEME_SRC" ]; then
  warn "OS1 ThemeManager skipped: no valid source folder found"
  exit 0
fi

isOriginThemeMng=$(find "$MAIN_FOLDER" -type d \( \
  -name "MIUIThemeManager" \
  -o -name "MIUIThemeManagerT" \
  -o -name "MIUIThemeManagerGlobal" \
  -o -name "ThemeManager" \
\) 2>/dev/null)

if [ -n "$isOriginThemeMng" ]; then
  rm -rf $isOriginThemeMng
  mods "OS1 ThemeManager: old ThemeManager removed"
fi

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

cp -a "$THEME_SRC"/. "$TARGET_DIR"/
mods "OS1 ThemeManager: applied Android $androidVER source"

mkdir -p "$PERM_TARGET"

if [ -f "$PERM_FILE" ]; then
  cp -f "$PERM_FILE" "$PERM_TARGET/"
  mods "OS1 ThemeManager: permissions copied"
else
  warn "OS1 ThemeManager permissions file missing: $PERM_FILE"
fi

mods "Modify ThemeManager Done"