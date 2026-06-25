# DeadZone: skip OS3 launcher replacement on POCO devices
DZ_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DZ_WORK_DIR="${work_dir:-$(cd "$DZ_SCRIPT_DIR/../../../.." && pwd)}"

dz_is_poco=false

if grep -RIsi "poco" "$DZ_WORK_DIR/bin/ddevice" 2>/dev/null | grep -qi "poco"; then
    dz_is_poco=true
elif grep -RIsi "POCO" \
    "$DZ_WORK_DIR/build/baserom/images/vendor" \
    "$DZ_WORK_DIR/build/baserom/images/odm" \
    "$DZ_WORK_DIR/build/baserom/images/product" \
    "$DZ_WORK_DIR/build/baserom/images/system_ext" 2>/dev/null | grep -qi "POCO"; then
    dz_is_poco=true
fi

if [[ "$dz_is_poco" == "true" ]]; then
    if declare -F mods >/dev/null 2>&1; then
        mods "[OS3 Launcher] Skip: POCO device detected, keep default launcher."
    else
        echo "[OS3 Launcher] Skip: POCO device detected, keep default launcher."
    fi
    exit 0
fi
work_dir=$(pwd)
source $work_dir/functions.sh
MAIN_FOLDER="$work_dir/build/baserom/images"
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)
regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
androidVER=$(cat $work_dir/bin/ddevice/androidver.txt)
device_code=$(cat $work_dir/bin/ddevice/device_f.txt)

isOriginHome=$(find "$MAIN_FOLDER" -type d \( -name "MiuiHomeT" -o -name "MiuiHome" -o -name "MiLauncherGlobal" -o -name "PocoHome" -o -name "PocoLauncher" \))


if grep -qw "$device_code" "$work_dir/bin/ddevice/data/pad_data.txt"; then
  mods "Pad Device!!Skipping Adding Launcher"
else
 if [[ $rom_os == "OS3" ]];then 
    rm -rf $isOriginHome
    mkdir -p $work_dir/build/baserom/images/product/priv-app/MiuiHome
    cp -rf $work_dir/bin/modfile/OS3/launcher/MiuiHome/* $work_dir/build/baserom/images/product/priv-app/MiuiHome
    cp -rf $work_dir/bin/modfile/OS3/launcher/XiaomiEUExt $work_dir/build/baserom/images/product/priv-app/
    cp -rf $work_dir/bin/modfile/OS3/launcher/permissions/privapp_whitelist_eu.xiaomi.ext.xml $work_dir/build/baserom/images/product/etc/permissions/
    cp -rf $work_dir/bin/modfile/OS3/launcher/permissions/privapp_whitelist_com.miui.home.xml $work_dir/build/baserom/images/product/etc/permissions/
 fi
fi
mods "Modify Home Done"