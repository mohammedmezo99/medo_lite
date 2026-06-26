#!/bin/bash
set -e

work_dir=$(pwd)
source "$work_dir/functions.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_NAME="$(basename "$(dirname "$SCRIPT_DIR")")"

MAIN_FOLDER="$work_dir/build/baserom/images"
rom_os=$(cat "$work_dir/bin/ddevice/rom_os.txt")
device_code=$(cat "$work_dir/bin/ddevice/device_f.txt")

LAUNCHER_DIR="$work_dir/bin/modfile/$OS_NAME/launcher"

MIUI_HOME_SRC="$LAUNCHER_DIR/MiuiHome"
XIAOMI_EU_EXT_SRC="$LAUNCHER_DIR/XiaomiEUExt"
PERMISSIONS_SRC="$LAUNCHER_DIR/permissions"
OVERLAY_SRC_1="$LAUNCHER_DIR/overlay"
OVERLAY_SRC_2="$LAUNCHER_DIR/product/overlay"

PRODUCT="$MAIN_FOLDER/product"
SYSTEM_EXT="$MAIN_FOLDER/system_ext"
VENDOR="$MAIN_FOLDER/vendor"

INIT_RC="$SYSTEM_EXT/etc/init/init.miui.ext.rc"
PRODUCT_PERMISSIONS="$PRODUCT/etc/permissions"
PRIVAPP_XML="$PRODUCT/etc/permissions/privapp-permissions-product.xml"
PRODUCT_OVERLAY="$PRODUCT/overlay"
VENDOR_PROP="$VENDOR/build.prop"

MOD_NAME="$OS_NAME MIUI Launcher"

find_apk_by_package() {
  local search_dir="$1"
  local wanted_pkg="$2"

  [ -d "$search_dir" ] || return 1

  while IFS= read -r apk; do
    pkg="$(aapt dump badging "$apk" 2>/dev/null | sed -n "s/package: name='\([^']*\)'.*/\1/p" | head -n1)"
    if [ "$pkg" = "$wanted_pkg" ]; then
      printf '%s\n' "$apk"
      return 0
    fi
  done < <(find "$search_dir" -type f -iname "*.apk" 2>/dev/null)

  return 1
}

detect_poco_device() {
  if grep -RIsi "poco" "$work_dir/bin/ddevice" 2>/dev/null | grep -qi "poco"; then
    return 0
  fi

  if grep -RIsi "POCO" \
    "$MAIN_FOLDER/vendor" \
    "$MAIN_FOLDER/odm" \
    "$MAIN_FOLDER/product" \
    "$MAIN_FOLDER/system_ext" 2>/dev/null | grep -qi "POCO"; then
    return 0
  fi

  if find_apk_by_package "$PRODUCT" "com.mi.android.globallauncher" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

remove_origin_launchers() {
  isOriginHome=$(find "$MAIN_FOLDER" -type d \( \
    -name "MiuiHomeT" \
    -o -name "MiuiHome" \
    -o -name "MiLauncherGlobal" \
    -o -name "PocoHome" \
    -o -name "PocoLauncher" \
    -o -name "GlobalLauncher" \
  \) 2>/dev/null)

  if [ -n "$isOriginHome" ]; then
    rm -rf $isOriginHome
    mods "[$MOD_NAME] old launcher folders removed"
  fi
}

remove_poco_launcher_by_package() {
  removed=0

  for scan_dir in "$PRODUCT/priv-app" "$PRODUCT/app" "$PRODUCT/data-app"; do
    [ -d "$scan_dir" ] || continue

    while IFS= read -r apk; do
      pkg="$(aapt dump badging "$apk" 2>/dev/null | sed -n "s/package: name='\([^']*\)'.*/\1/p" | head -n1)"

      if [ "$pkg" = "com.mi.android.globallauncher" ]; then
        app_dir="$(dirname "$apk")"
        rm -rf "$app_dir"
        removed=$((removed + 1))
        mods "[$MOD_NAME] removed POCO launcher: $app_dir"
      fi
    done < <(find "$scan_dir" -type f -iname "*.apk" 2>/dev/null)
  done

  if [ "$removed" -eq 0 ]; then
    warn "[$MOD_NAME] no POCO launcher APK removed by package name"
  fi
}

patch_poco_init() {
  if [ -f "$INIT_RC" ]; then
    if grep -q "com.mi.android.globallauncher" "$INIT_RC"; then
      sed -i "s/com.mi.android.globallauncher/com.miui.home/g" "$INIT_RC"
      mods "[$MOD_NAME] system_ext init patched: com.miui.home"
    else
      mods "[$MOD_NAME] init already clean"
    fi
  else
    warn "[$MOD_NAME] init.miui.ext.rc not found"
  fi
}

add_miui_home_privapp_permissions() {
  mkdir -p "$PRODUCT_PERMISSIONS"

  python3 - "$PRIVAPP_XML" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])

block = '''    <privapp-permissions package="com.miui.home">
        <permission name="android.permission.BIND_APPWIDGET"/>
        <permission name="android.permission.BIND_WALLPAPER"/>
        <permission name="android.permission.CHANGE_COMPONENT_ENABLED_STATE"/>
        <permission name="android.permission.CHANGE_CONFIGURATION"/>
        <permission name="android.permission.DELETE_PACKAGES"/>
        <permission name="android.permission.DUMP"/>
        <permission name="android.permission.INTERACT_ACROSS_USERS"/>
        <permission name="android.permission.MANAGE_USERS"/>
        <permission name="android.permission.MEDIA_CONTENT_CONTROL"/>
        <permission name="android.permission.MOUNT_UNMOUNT_FILESYSTEMS"/>
        <permission name="android.permission.PACKAGE_USAGE_STATS"/>
        <permission name="android.permission.READ_FRAME_BUFFER"/>
        <permission name="android.permission.SET_PROCESS_LIMIT"/>
        <permission name="android.permission.SET_WALLPAPER_COMPONENT"/>
        <permission name="android.permission.START_TASKS_FROM_RECENTS"/>
        <permission name="android.permission.CONTROL_REMOTE_APP_TRANSITION_ANIMATIONS"/>
        <permission name="android.permission.INTERNAL_SYSTEM_WINDOW"/>
        <permission name="android.permission.REAL_GET_TASKS"/>
        <permission name="android.permission.STATUS_BAR"/>
        <permission name="android.permission.UPDATE_APP_OPS_STATS"/>
        <permission name="android.permission.UPDATE_DEVICE_STATS"/>
        <permission name="android.permission.WRITE_SECURE_SETTINGS"/>
        <permission name="android.permission.MANAGE_ACTIVITY_STACKS"/>
        <permission name="android.permission.FORCE_STOP_PACKAGES"/>
        <permission name="android.permission.READ_PRIVILEGED_PHONE_STATE"/>
        <permission name="android.permission.ACCESS_THEME"/>
        <permission name="android.permission.BROADCAST_CLOSE_SYSTEM_DIALOGS"/>
    </privapp-permissions>'''

if path.exists():
    text = path.read_text(encoding="utf-8", errors="ignore")
else:
    text = '<?xml version="1.0" encoding="utf-8"?>\n<permissions>\n</permissions>\n'

if 'privapp-permissions package="com.miui.home"' not in text:
    if "</permissions>" in text:
        text = text.replace("</permissions>", block + "\n</permissions>")
    else:
        text = '<?xml version="1.0" encoding="utf-8"?>\n<permissions>\n' + text + "\n" + block + "\n</permissions>\n"
    path.write_text(text, encoding="utf-8")
    print("[INFO] - com.miui.home added to privapp-permissions-product.xml")
else:
    print("[INFO] - com.miui.home already exists in privapp-permissions-product.xml")
PY
}

copy_launcher_files() {
  mkdir -p "$PRODUCT/priv-app"
  mkdir -p "$PRODUCT_PERMISSIONS"

  if [ -d "$MIUI_HOME_SRC" ] && [ -f "$MIUI_HOME_SRC/MiuiHome.apk" ]; then
    rm -rf "$PRODUCT/priv-app/MiuiHome"
    cp -a "$MIUI_HOME_SRC" "$PRODUCT/priv-app/MiuiHome"
    mods "[$MOD_NAME] MiuiHome copied to product/priv-app"
  else
    warn "[$MOD_NAME] MiuiHome source missing"
    return 1
  fi

  if [ -d "$XIAOMI_EU_EXT_SRC" ] && [ -f "$XIAOMI_EU_EXT_SRC/XiaomiEUExt.apk" ]; then
    rm -rf "$PRODUCT/priv-app/XiaomiEUExt"
    cp -a "$XIAOMI_EU_EXT_SRC" "$PRODUCT/priv-app/XiaomiEUExt"
    mods "[$MOD_NAME] XiaomiEUExt copied"
  fi

  if [ -d "$PERMISSIONS_SRC" ]; then
    cp -a "$PERMISSIONS_SRC"/. "$PRODUCT_PERMISSIONS"/
    mods "[$MOD_NAME] whitelist permissions copied"
  fi
}

copy_launcher_overlay() {
  mkdir -p "$PRODUCT_OVERLAY"

  if [ -d "$OVERLAY_SRC_1" ] && find "$OVERLAY_SRC_1" -mindepth 1 2>/dev/null | grep -q .; then
    cp -a "$OVERLAY_SRC_1"/. "$PRODUCT_OVERLAY"/
    mods "[$MOD_NAME] overlay copied from launcher/overlay"
  elif [ -d "$OVERLAY_SRC_2" ] && find "$OVERLAY_SRC_2" -mindepth 1 2>/dev/null | grep -q .; then
    cp -a "$OVERLAY_SRC_2"/. "$PRODUCT_OVERLAY"/
    mods "[$MOD_NAME] overlay copied from launcher/product/overlay"
  else
    warn "[$MOD_NAME] no launcher overlay found, skipping product/overlay"
  fi
}

clean_vendor_privapp_enforce() {
  if [ -f "$VENDOR_PROP" ]; then
    if grep -q "^ro.control_privapp_permissions=enforce$" "$VENDOR_PROP"; then
      sed -i "/^ro.control_privapp_permissions=enforce$/d" "$VENDOR_PROP"
      mods "[$MOD_NAME] removed ro.control_privapp_permissions=enforce"
    else
      mods "[$MOD_NAME] vendor privapp enforcement line not present"
    fi
  else
    warn "[$MOD_NAME] vendor/build.prop not found"
  fi
}

if [[ "$rom_os" != "$OS_NAME" ]]; then
  warn "[$MOD_NAME] skipped: ROM is not $OS_NAME"
  exit 0
fi

if grep -qw "$device_code" "$work_dir/bin/ddevice/data/pad_data.txt"; then
  mods "Pad Device!! Skipping Adding Launcher"
  exit 0
fi

if detect_poco_device; then
  mods "[$MOD_NAME] POCO detected: applying MIUI Launcher mod"

  remove_poco_launcher_by_package
  remove_origin_launchers
  patch_poco_init
  copy_launcher_files
  add_miui_home_privapp_permissions
  copy_launcher_overlay
  clean_vendor_privapp_enforce

  mods "Modify Home Done"
  exit 0
fi

mods "[$MOD_NAME] Non-POCO device: applying normal launcher"

remove_origin_launchers
copy_launcher_files
add_miui_home_privapp_permissions
copy_launcher_overlay

mods "Modify Home Done"