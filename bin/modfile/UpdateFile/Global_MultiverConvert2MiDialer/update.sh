work_dir=$(pwd)
source $work_dir/functions.sh
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)
MAIN_FOLDER="$work_dir/build/baserom/images"
regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
androidVER=$(cat $work_dir/bin/ddevice/androidver.txt)
MAIN_FOLDER="$work_dir/build/baserom/images"
existXiaomiTelephonyService=$(
    find "$MAIN_FOLDER" -type d \
    \( -name "*MIUIContacts*" -o -name "*InCallUI*" -o -name "*MiuiMms*" \
       -o -name "*MiuiTelephony*" -o -name "*XiaomiTelephony*" -o -name "*MiuiPhone*" -o -name "*XiaomiInCallUI*" -o -name "*XiaomiMiuiContacts*" -o -name "*XiaomiMiuiMms*" \)
)

isGoogleMessages=$(
    find "$MAIN_FOLDER" -type d \
    \( -name "Messages" -o -name "Messages_arm64_xxhdpi" -o -name "Messages_arm64_xxxhdpi" \)
)

isGoogleContacts=$(
    find "$MAIN_FOLDER" -type d -name "*GoogleContacts*"
)

isGDialer=$(
    find "$MAIN_FOLDER" -type d \
    \( -name "GoogleDialer" -o -name "GoogleDialer_arm64" \)
)

isGMSConfig=$(find "$MAIN_FOLDER" -type f -name "GmsConfigOverlayComms.apk")


cleanStuff() {
    mods "Cleaning Google Dialer Services"
    rm -rf $isGDialer
    rm -rf $isGoogleMessages
    rm -rf $isGoogleContacts
    rm -rf $isGMSConfig
}


if [[ $regionTYPE == *"Global"* ]]; then

mods "Apply MIUI Dialer to Global ROM..."
cleanStuff

if [[ -n "$existXiaomiTelephonyService" ]];then
    mods "MIUI Service found. Deleting..."
    echo "$existXiaomiTelephonyService" | while IFS= read -r dir; do
        rm -rf "$dir"
    done
else
    mods "MIUI Service not found. Continue..."
fi

if [[ $androidVER == "13" ]];then
    mods "Copying MIUI Dialer..."
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/A13/* $work_dir/build/baserom/images/product/priv-app/
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/overlay/* $work_dir/build/baserom/images/product/overlay/
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/permissions/* $work_dir/build/baserom/images/product/etc/permissions/
elif [[ $androidVER == "14" ]];then
    mods "Copying MIUI Dialer..."
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/A14/* $work_dir/build/baserom/images/product/priv-app/
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/overlay/* $work_dir/build/baserom/images/product/overlay/
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/permissions/* $work_dir/build/baserom/images/product/etc/permissions/
elif [[ $androidVER == "15" ]];then
    mods "Copying MIUI Dialer..."
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/A15/* $work_dir/build/baserom/images/product/priv-app/
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/overlay/* $work_dir/build/baserom/images/product/overlay/
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/permissions/* $work_dir/build/baserom/images/product/etc/permissions/
elif [[ $androidVER == "16" ]];then
    mods "Copying MIUI Dialer..."
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/A16/* $work_dir/build/baserom/images/product/priv-app/
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/overlay/* $work_dir/build/baserom/images/product/overlay/
    cp -rf $work_dir/bin/modfile/UpdateFile/Global_MultiverConvert2MiDialer/permissions/* $work_dir/build/baserom/images/product/etc/permissions/
else
    mods "Unsupported Android version: $androidVER"
fi
fi