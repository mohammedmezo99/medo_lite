work_dir=$(pwd)
source $work_dir/functions.sh
MAIN_FOLDER="$work_dir/build/baserom/images"
repS="python3 $work_dir/bin/strRep.py"
deviceTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
androidVER=$(cat $work_dir/bin/ddevice/androidver.txt)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)
APKEDITOR="java -jar $work_dir/bin/apktool/apke.jar"
repS="python3 $work_dir/bin/strRep.py"



if [[ $androidVER == "16" ]]; then
mods "Patching Notification Fix to SystemUI"
#ready for patch
mkdir -p $work_dir/apk_temp
isMiuiSystemUIDIR=$(find "$MAIN_FOLDER" -type d -name "MiuiSystemUI")
isMiuiSystemUI=$(find "$MAIN_FOLDER" -type f -name "MiuiSystemUI.apk")
$APKEDITOR d -t raw -f -no-dex-debug -i $isMiuiSystemUI -o $work_dir/apk_temp/isMiuiSystemUI.apk.out >/dev/null 2>&1
FOLDER="$work_dir/apk_temp/isMiuiSystemUI.apk.out"
find_and_replace() {
    local search=$1
    local replace=$2
    local base_dir=$FOLDER
    local files=(
        "QSTileHost.smali"
        "MiuiNotificationInterruptStateProviderImpl.smali"
        "NotificationUtil.smali"
        "MiuiOperatorCustomizedPolicy.smali"
        "MiuiBaseNotifUtil.smali"
        "NotificationSettingsManager.smali"
        "MiuiCarrierTextController.smali"
        "MiuiCellularIconVM\$special\$\$inlined\$combine\$1\$3.smali"
        "MiuiMobileIconBinder\$bind\$1\$1\$10.smali"
        "MiuiMobileIconBinder\$bind\$1\$1.smali"
    )

    for file in "${files[@]}"; do
        file_path=$(find "$base_dir" -name "$file")
        if [[ -n $file_path ]]; then
            if grep -q "$search" "$file_path"; then
                sed -i "s|$search|$replace|g" "$file_path"
            fi
        fi
    done
} 

  find_and_replace "Lmiui/os/Build;->IS_INTERNATIONAL_BUILD:Z" "Lmiui/os/xBuild;->IS_INTERNATIONAL_BUILD:Z"
  find_and_replace "Lcom/miui/utils/configs/MiuiConfigs;->IS_INTERNATIONAL_BUILD:Z" "Lmiui/os/xBuild;->IS_INTERNATIONAL_BUILD:Z"


#Finishing
MiuiSystemUI=$(basename $isMiuiSystemUI)
$APKEDITOR b -f -i $work_dir/apk_temp/isMiuiSystemUI.apk.out -o $work_dir/apk_temp/final/$MiuiSystemUI >/dev/null 2>&1

if [ -f "$work_dir/apk_temp/final/$MiuiSystemUI" ]; then
    rm -rf $isMiuiSystemUIDIR/oat
	rm -rf $isMiuiSystemUIDIR/$MiuiSystemUI
    cp -rf $work_dir/apk_temp/final/$MiuiSystemUI $isMiuiSystemUIDIR
fi

rm -rf $work_dir/apk_temp
mods "Done"

fi