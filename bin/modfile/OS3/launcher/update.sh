#!/bin/bash
set -e

work_dir=$(pwd)
source "$work_dir/functions.sh"

MAIN_FOLDER="$work_dir/build/baserom/images"
rom_os=$(cat "$work_dir/bin/ddevice/rom_os.txt")
device_code=$(cat "$work_dir/bin/ddevice/device_f.txt")

if [[ "$rom_os" != "OS3" ]]; then
    warn "[OS3 MIUI Launcher] skipped: ROM is not OS3"
    exit 0
fi

if grep -qw "$device_code" "$work_dir/bin/ddevice/data/pad_data.txt"; then
    mods "Pad Device!! Skipping Adding Launcher"
    exit 0
fi

isOriginHome=$(find "$MAIN_FOLDER" -type d \( \
    -name "MiuiHomeT" \
    -o -name "MiuiHome" \
    -o -name "MiLauncherGlobal" \
    -o -name "PocoHome" \
    -o -name "PocoLauncher" \
\) 2>/dev/null)

if [ -n "$isOriginHome" ]; then
    rm -rf $isOriginHome
fi

mkdir -p "$MAIN_FOLDER/product/priv-app"
mkdir -p "$MAIN_FOLDER/product/etc/permissions"

cp -rf "$work_dir/bin/modfile/OS3/launcher/MiuiHome" "$MAIN_FOLDER/product/priv-app/"
cp -rf "$work_dir/bin/modfile/OS3/launcher/XiaomiEUExt" "$MAIN_FOLDER/product/priv-app/"
cp -rf "$work_dir/bin/modfile/OS3/launcher/permissions/." "$MAIN_FOLDER/product/etc/permissions/"

mods "Modify Home Done"
