#!/bin/bash

baserom="$1"
work_dir=$(pwd)
source $work_dir/functions.sh
# Check whether it is a local package or a link
if [ ! -f "${baserom}" ] && echo "${baserom}" | grep -Eq '^https?://'; then
    info "Download link detected, starting download..."

    output_name=""
    is_sourceforge=false
    sf_project=""
    sf_path=""

    # Normalize SourceForge /download links and use real mirror URLs.
    if echo "${baserom}" | grep -qE '^https?://sourceforge\.net/projects/[^/]+/files/.+/download'; then
        is_sourceforge=true
        sf_project="$(printf '%s\n' "${baserom}" | sed -E 's#^https?://sourceforge\.net/projects/([^/]+)/files/.*#\1#')"
        sf_path="$(printf '%s\n' "${baserom}" | sed -E 's#^https?://sourceforge\.net/projects/[^/]+/files/(.*)/download.*#\1#')"
        output_name="$(basename "${sf_path}")"
        info "SourceForge link detected: ${output_name}"
    fi

    rm -f "${work_dir}"/*.aria2

    valid_archive() {
        local file="$1"
        if [ -z "$file" ] || [ ! -f "$file" ]; then
            return 1
        fi

        # SourceForge error pages are usually HTML/text, often small.
        if file "$file" | grep -qiE 'HTML|text|XML'; then
            return 1
        fi

        case "$file" in
            *.zip|*.tgz|*.tar.gz|*.tar|*.img)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }

    download_ok=false

    if [ "${is_sourceforge}" = true ]; then
        # Try direct mirrors first. downloads.sourceforge.net often returns HTML/403 in GitHub Actions.
        sf_urls=(
            "https://master.dl.sourceforge.net/project/${sf_project}/${sf_path}"
            "https://netix.dl.sourceforge.net/project/${sf_project}/${sf_path}"
            "https://versaweb.dl.sourceforge.net/project/${sf_project}/${sf_path}"
            "https://netcologne.dl.sourceforge.net/project/${sf_project}/${sf_path}"
            "https://phoenixnap.dl.sourceforge.net/project/${sf_project}/${sf_path}"
            "https://downloads.sourceforge.net/project/${sf_project}/${sf_path}?use_mirror=master"
        )

        rm -f "${output_name}" "${output_name}.aria2" 2>/dev/null || true

        for sf_url in "${sf_urls[@]}"; do
            info "Trying SourceForge mirror: ${sf_url}"

            rm -f "${output_name}" "${output_name}.aria2" 2>/dev/null || true

            curl -L --fail --retry 3 --retry-delay 5 \
                -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
                -H "Accept: application/octet-stream,*/*" \
                -H "Referer: https://sourceforge.net/" \
                -o "${output_name}" "${sf_url}" && {
                    if valid_archive "${output_name}"; then
                        download_ok=true
                        break
                    else
                        warn "Mirror returned non-ROM content, trying next mirror..."
                        rm -f "${output_name}" 2>/dev/null || true
                    fi
                }
        done

        if [ "${download_ok}" = true ]; then
            baserom="${output_name}"
            info "BASEROM: ${baserom}"
        else
            error "Download error: SourceForge mirrors did not return a valid ROM archive."
            exit 1
        fi

    else
        before_list="$(mktemp)"
        after_list="$(mktemp)"
        find "${work_dir}" -maxdepth 1 -type f -printf '%f\n' | sort > "${before_list}"

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
            "${baserom}" && download_ok=true

        if [ "${download_ok}" != true ]; then
            info "aria2c failed, trying curl fallback..."
            curl -L --fail --retry 5 --retry-delay 10 \
                -A "Mozilla/5.0" \
                -OJ "${baserom}" && download_ok=true
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

        if ! valid_archive "${work_dir}/${baserom}"; then
            error "Download error: link downloaded an HTML/text page, not a ROM archive. Use a direct downloadable ROM link."
            exit 1
        fi

        info "BASEROM: ${baserom}"
    fi

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

