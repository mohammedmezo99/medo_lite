#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$work_dir/functions.sh"

MAIN_FOLDER="$work_dir/build/baserom/images"
rom_os=$(cat "$work_dir/bin/ddevice/rom_os.txt")
device_code=$(cat "$work_dir/bin/ddevice/device_f.txt")
device_name_file="$work_dir/bin/ddevice/device_name.txt"
name_devices_file="$work_dir/bin/ddevice/name_devices.txt"
codename_file="$work_dir/bin/ddevice/codename.txt"

MOD_NAME="POCO MIUI Launcher Fix"
PRODUCT_DIR="$MAIN_FOLDER/product"
SYSTEM_EXT_DIR="$MAIN_FOLDER/system_ext"
VENDOR_DIR="$MAIN_FOLDER/vendor"

INIT_RC="$SYSTEM_EXT_DIR/etc/init/init.miui.ext.rc"
PRODUCT_PERMISSIONS_DIR="$PRODUCT_DIR/etc/permissions"
PRIVAPP_XML="$PRODUCT_PERMISSIONS_DIR/privapp-permissions-product.xml"
PRODUCT_OVERLAY_DIR="$PRODUCT_DIR/overlay"
VENDOR_PROP="$VENDOR_DIR/build.prop"
POCO_FIX_ALLOW_CODENAME_MATCH="${POCO_FIX_ALLOW_CODENAME_MATCH:-false}"
POCO_CODENAMES=(
    alioth munch ingres marble mondrian peridot vermeer onyx zorn miro
    annibale myron garnet rodin duchamp redwood vayu bhima sky breeze flame
)

log_mod() {
    mods "[$MOD_NAME] $1"
}

log_warn() {
    warn "[$MOD_NAME] $1"
}

contains_poco_text() {
    local value="$1"
    [[ "$value" =~ (^|[^[:alnum:]])POCO([^[:alnum:]]|$) ]]
}

contains_poco_metadata() {
    local file="$1"
    [ -f "$file" ] || return 1
    while IFS= read -r line; do
        contains_poco_text "$line" && return 0
    done < "$file"
    return 1
}

read_first_value() {
    local file="$1"
    [ -f "$file" ] || return 1
    IFS= read -r line < "$file" || return 1
    printf '%s\n' "$line"
}

contains_poco_buildprop_file() {
    local file="$1"
    [ -f "$file" ] || return 1
    while IFS='=' read -r key value; do
        case "$key" in
            ro.product.marketname|ro.product.model|ro.product.vendor.marketname|ro.product.vendor.model|ro.vendor.product.marketname|ro.vendor.product.model|ro.product.name|ro.product.device|ro.build.product)
                contains_poco_text "$value" && return 0
                ;;
        esac
    done < "$file"
    return 1
}

has_poco_launcher_folder() {
    local dir="$1"
    [ -d "$dir" ]
}

is_known_poco_codename() {
    local value="$1"
    local lowered="${value,,}"
    local codename
    for codename in "${POCO_CODENAMES[@]}"; do
        [[ "$lowered" == "$codename" ]] && return 0
    done
    return 1
}

is_poco_device() {
    local metadata_match=1
    local buildprop_match=1
    local launcher_match=1
    local codename_match=1
    local codename_value=""
    local metadata_files=(
        "$device_name_file"
        "$name_devices_file"
        "$work_dir/bin/ddevice/device_f.txt"
        "$codename_file"
    )
    local buildprop_files=(
        "$MAIN_FOLDER/product/build.prop"
        "$MAIN_FOLDER/system/build.prop"
        "$MAIN_FOLDER/system/system/build.prop"
        "$MAIN_FOLDER/system_ext/build.prop"
        "$MAIN_FOLDER/vendor/build.prop"
        "$MAIN_FOLDER/odm/build.prop"
    )
    local launcher_dirs=(
        "$PRODUCT_DIR/app/PocoHome"
        "$PRODUCT_DIR/priv-app/PocoHome"
        "$PRODUCT_DIR/data-app/PocoHome"
        "$PRODUCT_DIR/app/PocoLauncher"
        "$PRODUCT_DIR/priv-app/PocoLauncher"
        "$PRODUCT_DIR/data-app/PocoLauncher"
        "$PRODUCT_DIR/app/GlobalLauncher"
        "$PRODUCT_DIR/priv-app/GlobalLauncher"
        "$PRODUCT_DIR/data-app/GlobalLauncher"
    )
    local file launcher_dir

    log_mod "Detection: metadata"
    for file in "${metadata_files[@]}"; do
        if contains_poco_metadata "$file"; then
            metadata_match=0
            break
        fi
    done

    log_mod "Detection: build.prop"
    for file in "${buildprop_files[@]}"; do
        if contains_poco_buildprop_file "$file"; then
            buildprop_match=0
            break
        fi
    done

    log_mod "Detection: launcher folders"
    for launcher_dir in "${launcher_dirs[@]}"; do
        if has_poco_launcher_folder "$launcher_dir"; then
            launcher_match=0
            break
        fi
    done

    codename_value="$(read_first_value "$codename_file" || true)"
    if is_known_poco_codename "$device_code" || is_known_poco_codename "$codename_value"; then
        codename_match=0
    fi

    if [[ $metadata_match -eq 0 || $buildprop_match -eq 0 || $launcher_match -eq 0 ]]; then
        log_mod "Detection result: POCO"
        return 0
    fi

    if [[ $codename_match -eq 0 && "${POCO_FIX_ALLOW_CODENAME_MATCH,,}" == "true" ]]; then
        log_mod "Detection result: POCO"
        return 0
    fi

    log_mod "Detection result: non-POCO"
    return 1
}

resolve_source_dir() {
    local relative_path="$1"
    local updatefile_src="$SCRIPT_DIR/poco_miui_launcher_fix/$rom_os/$relative_path"
    local fallback_src="$work_dir/bin/modfile/$rom_os/launcher/$relative_path"

    if [ -e "$updatefile_src" ]; then
        printf '%s\n' "$updatefile_src"
        return 0
    fi

    if [ -e "$fallback_src" ]; then
        printf '%s\n' "$fallback_src"
        return 0
    fi

    return 1
}

patch_system_ext_init() {
    if [ -f "$INIT_RC" ] && grep -q 'com\.mi\.android\.globallauncher' "$INIT_RC"; then
        sed -i 's/com\.mi\.android\.globallauncher/com.miui.home/g' "$INIT_RC"
        log_mod "patched init.miui.ext.rc"
    fi
}

remove_poco_launcher_dirs() {
    local removed=0
    local fixed_names=("PocoHome" "PocoLauncher" "GlobalLauncher" "MiLauncherGlobal")
    local scan_dirs=("$PRODUCT_DIR/app" "$PRODUCT_DIR/priv-app" "$PRODUCT_DIR/data-app")
    local scan_dir name

    for scan_dir in "${scan_dirs[@]}"; do
        [ -d "$scan_dir" ] || continue

        for name in "${fixed_names[@]}"; do
            if [ -d "$scan_dir/$name" ]; then
                rm -rf "$scan_dir/$name"
                removed=1
                log_mod "removed $scan_dir/$name"
            fi
        done
    done

    if [ "$removed" -eq 0 ]; then
        log_warn "no POCO launcher folders found to remove"
    fi
}

copy_directory_if_present() {
    local label="$1"
    local src="$2"
    local dest="$3"

    if [ ! -d "$src" ]; then
        log_warn "$label source missing: $src"
        return 1
    fi

    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    log_mod "$label copied"
    return 0
}

copy_permissions_if_present() {
    local src="$1"
    mkdir -p "$PRODUCT_PERMISSIONS_DIR"

    if [ -d "$src" ]; then
        cp -a "$src"/. "$PRODUCT_PERMISSIONS_DIR"/
        log_mod "whitelist permissions copied"
    else
        log_warn "permissions source missing"
    fi
}

ensure_privapp_block() {
    mkdir -p "$PRODUCT_PERMISSIONS_DIR"

    if [ ! -f "$PRIVAPP_XML" ]; then
        cat > "$PRIVAPP_XML" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<permissions>
</permissions>
EOF
    fi

    if grep -q 'privapp-permissions package="com.miui.home"' "$PRIVAPP_XML"; then
        log_mod "privapp-permissions block already present"
        return 0
    fi

    python3 - "$PRIVAPP_XML" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
block = """    <privapp-permissions package="com.miui.home">
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
    </privapp-permissions>"""

text = path.read_text(encoding="utf-8", errors="ignore")
if "</permissions>" in text:
    text = text.replace("</permissions>", block + "\n</permissions>", 1)
else:
    text = '<?xml version="1.0" encoding="utf-8"?>\n<permissions>\n' + text + "\n" + block + "\n</permissions>\n"
path.write_text(text, encoding="utf-8")
PY

    log_mod "privapp-permissions block added"
}

copy_overlay_if_present() {
    local overlay_src
    local fallback_product_overlay="$work_dir/bin/modfile/$rom_os/launcher/product/overlay"

    if overlay_src=$(resolve_source_dir "overlay"); then
        mkdir -p "$PRODUCT_OVERLAY_DIR"
        cp -a "$overlay_src"/. "$PRODUCT_OVERLAY_DIR"/
        log_mod "overlay copied"
        return 0
    fi

    if [ -d "$fallback_product_overlay" ]; then
        mkdir -p "$PRODUCT_OVERLAY_DIR"
        cp -a "$fallback_product_overlay"/. "$PRODUCT_OVERLAY_DIR"/
        log_mod "overlay copied"
        return 0
    fi

    log_warn "overlay source missing, skipping"
}

remove_vendor_privapp_enforce() {
    if [ -f "$VENDOR_PROP" ] && grep -q '^ro.control_privapp_permissions=enforce$' "$VENDOR_PROP"; then
        sed -i '/^ro.control_privapp_permissions=enforce$/d' "$VENDOR_PROP"
        log_mod "removed ro.control_privapp_permissions=enforce"
    fi
}

if [[ "$rom_os" != "OS2" && "$rom_os" != "OS3" ]]; then
    log_mod "Skip: unsupported ROM OS $rom_os"
    exit 0
fi

if grep -qw "$device_code" "$work_dir/bin/ddevice/data/pad_data.txt"; then
    mods "Pad Device!! Skipping Adding Launcher"
    exit 0
fi

if ! is_poco_device; then
    log_mod "Skip: non-POCO device"
    exit 0
fi

miui_home_src=""
xiaomi_eu_ext_src=""
permissions_src=""

if ! miui_home_src=$(resolve_source_dir "MiuiHome"); then
    error "[$MOD_NAME] Missing MiuiHome source for $rom_os"
    exit 1
fi

xiaomi_eu_ext_src=$(resolve_source_dir "XiaomiEUExt" || true)
permissions_src=$(resolve_source_dir "permissions" || true)

patch_system_ext_init
remove_poco_launcher_dirs
copy_directory_if_present "MiuiHome" "$miui_home_src" "$PRODUCT_DIR/priv-app/MiuiHome"

if [ -n "$xiaomi_eu_ext_src" ]; then
    copy_directory_if_present "XiaomiEUExt" "$xiaomi_eu_ext_src" "$PRODUCT_DIR/priv-app/XiaomiEUExt" || true
else
    log_warn "XiaomiEUExt source missing"
fi

if [ -n "$permissions_src" ]; then
    copy_permissions_if_present "$permissions_src"
else
    log_warn "permissions source missing"
fi

ensure_privapp_block
copy_overlay_if_present
remove_vendor_privapp_enforce
log_mod "Done"
