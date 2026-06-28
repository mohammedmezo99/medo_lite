#!/bin/bash
# NullCode1337
cd "$(dirname "$0")" || exit 1

fastboot_bin="fastboot"
adb_bin="adb"
zstd_bin="zstd"

for tool in "$fastboot_bin" "$adb_bin" "$zstd_bin"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: '$tool' not found on PATH. Install platform-tools (adb/fastboot) and zstd, then try again."
        exit 1
    fi
done

DeviceCodeRom=$(cat "META-INF/Data/DeviceCode")

echo
echo "[i] - Read this information before flashing"
echo
echo "1. Our ROM, like most other custom ROMS, requires an unlocked bootloader! If your device is NOT, please close this window."
echo "2. You have to choose carefully else you will LOST ALL DATA!"
echo "3. THIS IS A FREE ROM!!! If you see someone sell or install this ROM for fees, please CONTACT MEZO NOW."
echo "4. We will NOT take responsibility if you brick your phone or lose all data while installing this ROM."
echo "5. Make sure you have downloaded the exact build for your device, else you might get bricked."
echo
echo "[i] - If you have read and agreed to all of the above, press any key to start the installation."
echo "[i] - Else, close this terminal (Ctrl+C)."
read -n 1 -s -r
echo

echo "========================================================================================="
echo " Please Choose Format Option Before Flash ROM"
echo
echo "   y = Format All Data (Clean Flash)"
echo "   n = Keep Data And Document (Dirty Flash)"
echo
echo "========================================================================================="
read -rp "Your choice {y/n}: " CHOICE
echo "========================================================================================="
echo "Make Sure Your Device Is In Fastboot Mode"
echo "If It Still Not Detected Please Install Driver"
echo "And Try Again..."
echo "========================================================================================="

DeviceCodeReal=$("$fastboot_bin" getvar product 2>&1 | grep "^product:" | awk '{print $2}')
fqlx=$("$fastboot_bin" getvar slot-count 2>&1 | grep "^slot-count:" | awk '{print $2}')

if [ "$fqlx" == "2" ]; then
    fqlx="AB"
else
    fqlx="A"
fi

if [ "$DeviceCodeReal" == "mars" ]; then
    DeviceCodeReal="star"
fi

if [[ "$DeviceCodeReal" != "$DeviceCodeRom"* ]]; then
    echo " Device codename does not match, your device is \"$DeviceCodeReal\". This rom file is for \"$DeviceCodeRom\"."
    read -n 1 -s -r -p "Press any key to exit..."
    echo
    exit 1
fi

for f in *.img.zst; do
    [ -e "$f" ] || continue
    par="${f%.img.zst}"
    rm -f "${par}.img"
    echo "  Extract $par ..."
    "$zstd_bin" -d "$f" -o "${par}.img"
done

for img in images/*; do
    [ -e "$img" ] || continue
    par="$(basename "$img")"
    par="${par%.*}"
    url="$img"
    if [ "$par" == "cust" ]; then
        "$fastboot_bin" flash "$par" "$url" >/dev/null 2>&1
    elif [ "$par" == "preloader_raw" ]; then
        "$fastboot_bin" flash preloader_a "$url" >/dev/null 2>&1
        "$fastboot_bin" flash preloader_b "$url" >/dev/null 2>&1
        "$fastboot_bin" flash preloader1 "$url" >/dev/null 2>&1
        "$fastboot_bin" flash preloader2 "$url" >/dev/null 2>&1
    elif [ "$fqlx" == "AB" ]; then
        "$fastboot_bin" flash "${par}_a" "$url"
        "$fastboot_bin" flash "${par}_b" "$url"
    else
        "$fastboot_bin" flash "$par" "$url"
    fi
done

if [ -f super.img ]; then
    "$fastboot_bin" flash super super.img
    rm -f super.img
fi

if [[ "$CHOICE" =~ ^[Yy]$ ]]; then
    echo "  Formatting..."
    "$fastboot_bin" erase frp >/dev/null 2>&1
    "$fastboot_bin" erase userdata >/dev/null 2>&1
    "$fastboot_bin" erase metadata >/dev/null 2>&1
    echo
fi

echo "  All done, Your Device Is Automatically Restarting..."
echo "  Now Wait For 10-15 Min For Booting"
echo
echo

if [ "$fqlx" == "AB" ]; then
    "$fastboot_bin" set_active a >/dev/null 2>&1
fi

"$fastboot_bin" reboot
read -n 1 -s -r -p "Press any key to exit..."
echo
exit 0