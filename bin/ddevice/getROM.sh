#!/bin/bash

baserom="$1"
work_dir=$(pwd)
source $work_dir/functions.sh
# Check whether it is a local package or a link
if [ ! -f "${baserom}" ] && echo "${baserom}" | grep -Eq '^https?://'; then
    info "Download link detected, starting download..."

    # Normalize SourceForge /download links to direct mirror URL
    output_name=""
    if echo "${baserom}" | grep -qE '^https?://sourceforge\.net/projects/[^/]+/files/.+/download'; then
        sf_project="$(printf '%s\n' "${baserom}" | sed -E 's#^https?://sourceforge\.net/projects/([^/]+)/files/.*#\1#')"
        sf_path="$(printf '%s\n' "${baserom}" | sed -E 's#^https?://sourceforge\.net/projects/[^/]+/files/(.*)/download.*#\1#')"
        output_name="$(basename "${sf_path}")"
        baserom="https://downloads.sourceforge.net/project/${sf_project}/${sf_path}"
        info "SourceForge link normalized: ${output_name}"
    fi

    rm -f "${work_dir}"/*.aria2
    before_list="$(mktemp)"
    after_list="$(mktemp)"
    find "${work_dir}" -maxdepth 1 -type f -printf '%f\n' | sort > "${before_list}"

    download_ok=false

    aria2c \
        --allow-overwrite=true \
        --auto-file-renaming=false \
        --continue=true \
        --max-tries=5 \
        --retry-wait=10 \
        --connect-timeout=30 \
        --timeout=120 \
        --file-allocation=none \
        -s10 -x10 -j10 \
        --header="User-Agent: Mozilla/5.0" \
        --header="Accept: */*" \
        ${output_name:+-o "$output_name"} \
        "${baserom}" && download_ok=true

    if [ "${download_ok}" != true ]; then
        info "aria2c failed, trying curl fallback..."
        if [ -n "${output_name}" ]; then
            curl -L --fail --retry 5 --retry-delay 10 \
                -A "Mozilla/5.0" \
                -H "Referer: https://sourceforge.net/" \
                -o "${output_name}" "${baserom}" && download_ok=true
        else
            curl -L --fail --retry 5 --retry-delay 10 \
                -A "Mozilla/5.0" \
                -OJ "${baserom}" && download_ok=true
        fi
    fi

    find "${work_dir}" -maxdepth 1 -type f -printf '%f\n' | sort > "${after_list}"

    downloaded_file="$(comm -13 "${before_list}" "${after_list}" | grep -E '\.(zip|tgz|tar\.gz|tar|img)$' | head -n 1 || true)"

    if [ -z "${downloaded_file}" ]; then
        downloaded_file="$(find "${work_dir}" -maxdepth 1 -type f -printf '%f\n' | grep -E '\.(zip|tgz|tar\.gz|tar|img)$' | sort -r | head -n 1 || true)"
    fi

    rm -f "${before_list}" "${after_list}"

    if [ "${download_ok}" != true ] || [ -z "${downloaded_file}" ] || [ ! -f "${work_dir}/${downloaded_file}" ]; then
        error "Download error: no valid ROM archive was downloaded."
        exit 1
    fi

    baserom="${downloaded_file}"

    if file "${work_dir}/${baserom}" | grep -qiE 'HTML|text'; then
        error "Download error: link downloaded an HTML/text page, not a ROM archive. Use a direct downloadable ROM link."
        exit 1
    fi

    info "BASEROM: ${baserom}"

elif [ -f "${baserom}" ]; then
    info "BASEROM: ${baserom}"
else
    error "BASEROM: Invalid parameter"
    exit 1
fi


# Get ROM Info
if [ "$(echo $baserom |grep miui_)" != "" ]; then
    device_code=$(basename $baserom |cut -d '_' -f 2)
    base_rom_code=$(echo "$baserom" | awk -F'_' '{print $3}')
elif [ "$(echo $baserom |grep xiaomi.eu_)" != "" ]; then
    device_code=$(basename $baserom |cut -d '_' -f 3)
    base_rom_code=$(echo "$baserom" | awk -F'_' '{print $3}')
elif [ "$(echo $baserom | grep -E '.*-ota_full-.*')" != "" ]; then
    device_code=$(basename $baserom | cut -d '-' -f 1)
    base_rom_code=$(basename $baserom | cut -d '-' -f 3)

    # Transform device_code
    device_code=$(echo $device_code | awk -F '_' '{
        if (NF == 1) {
            # If one part, e.g., shennong
            print toupper($1)
        } else if (NF == 2) {
            # If two parts, e.g., tapas_global
            print toupper($1) toupper(substr($2, 1, 1)) substr($2, 2)
        } else if (NF == 3) {
            # If three parts, e.g., houji_tw_global
            printf toupper($1) toupper($2) toupper(substr($3, 1, 1)) substr($3, 2)
        }
    }')
else
    device_code="YourDevice"
    base_rom_code="Unknown"
fi

device_f=$(echo $device_code | sed 's/\(Global\|EEAGlobal\|INGlobal\|IDGlobal\|RUGlobal\|TWGlobal\|TRGlobal\|JPGlobal\)$//' | tr '[:upper:]' '[:lower:]')

# Determine Device Type
info "Get Device Type"
if echo "$device_code" | grep -q 'EEAGlobal'; then
    DEVICE_TYPE="EEAGlobal"
elif echo "$device_code" | grep -q 'INGlobal'; then
    DEVICE_TYPE="INGlobal"
elif echo "$device_code" | grep -q 'IDGlobal'; then
    DEVICE_TYPE="IDGlobal"
elif echo "$device_code" | grep -q 'RUGlobal'; then
    DEVICE_TYPE="RUGlobal"
elif echo "$device_code" | grep -q 'JPGlobal'; then
    DEVICE_TYPE="JPGlobal"
elif echo "$device_code" | grep -q 'Global'; then
    DEVICE_TYPE="Global"
elif echo "$device_code" | grep -q 'TWGlobal'; then
    DEVICE_TYPE="TWGlobal"
elif echo "$device_code" | grep -q 'TRGlobal'; then
    DEVICE_TYPE="TRGlobal"
else
    DEVICE_TYPE="China"
fi

#Check MIUI or Hyper
if echo "$base_rom_code" | grep -q "OS1"; then
    ROM_OS="OS1"
elif echo "$base_rom_code" | grep -q "OS2"; then
    ROM_OS="OS2"
elif echo "$base_rom_code" | grep -q "OS3"; then
    ROM_OS="OS3"
elif echo "$base_rom_code" | grep -q "V14"; then
    ROM_OS="MIUI"
elif echo "$base_rom_code" | grep -q "V13"; then
    ROM_OS="MIUI"
else
    echo "Unsupport ROM Exiting..."
    exit 1
fi

echo $base_rom_code > $work_dir/bin/ddevice/base_rom_code.txt
echo $base_rom_code > $work_dir/bin/ddevice/os_code.txt
echo $device_code > $work_dir/bin/ddevice/device_code.txt
echo $DEVICE_TYPE > $work_dir/bin/ddevice/device_type.txt
echo $ROM_OS > $work_dir/bin/ddevice/rom_os.txt

