work_dir=$(pwd)
source $work_dir/functions.sh
MAIN_FOLDER="$work_dir/build/baserom/images"
repS="python3 $work_dir/bin/strRep.py"
deviceTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
APKEDITOR="java -jar $work_dir/bin/apktool/apke.jar"
repS="python3 $work_dir/bin/strRep.py"


patch "Patching PowerKeeper"
#ready for patch
mkdir -p $work_dir/apk_temp
isPowerKeeperDIR=$(find "$MAIN_FOLDER" -type d -name "PowerKeeper")
isPowerKeeper=$(find "$MAIN_FOLDER" -type f -name "PowerKeeper.apk")
$APKEDITOR d -t raw -f -no-dex-debug -i $isPowerKeeper -o $work_dir/apk_temp/isPowerKeeper.apk.out >/dev/null 2>&1
FOLDER="$work_dir/apk_temp/isPowerKeeper.apk.out"
find_and_replace() {
    local search=$1
    local replace=$2
    local base_dir=$FOLDER
    local files=(
        "BatteryLifeChecker.smali"
        "ProcCpuinfoManager.smali"
        "ProcCpuTimeInStateManager.smali"
        "ProcScreenPowerManager.smali"
        "CloudUpdateHideMode.smali"
        "CloudUpdateReceiver.smali"
        "LocalUpdateUtils.smali"
        "DeviceIdleController\$1.smali"
        "DeviceIdleController\$2.smali"
        "CustomerPowerCheck.smali"
        "UsageAppTracker.smali"
        "ThermalLogUploader.smali"
        "ThermalManager.smali"
        "MilletConfig.smali"
        "PeGameController.smali"
        "PowerCheckerCloudPolicy.smali"
        "DebugLabelSetting.smali"
        "DisplayFrameSetting.smali"
        "PadSleepModeController.smali"
        "PadSleepModeController\$SleepHandler.smali"
        "PhoneSleepModeController.smali"
        "PhoneSleepModeController\$SleepHandler.smali"
        "ThermalIECHandler.smali"
        "BaseEvent.smali"
        "TrackerManager\$PrivacyPolicy.smali"
        "PSUtils.smali"
        "UnionPowerConfig.smali"
        "ExtraVideoScenarioUtils.smali"
        "GmsObserver.smali"
        "Utils.smali"
        "PowerKeeperApplication.smali"
        "MIUIUtils.smali"
        "Network.smali"
        "DeviceUtil.smali"
        "XMPushService.smali"
        "PaymentManager.smali"
        "ExtraNetwork.smali"
        "ThemeManagerHelper.smali"
        "HostManager.smali"
        "YellowPageUtils.smali"
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

#Finishing
PowerKeeper=$(basename $isPowerKeeper)
$APKEDITOR b -f -i $work_dir/apk_temp/isPowerKeeper.apk.out -o $work_dir/apk_temp/final/$PowerKeeper >/dev/null 2>&1

if [ -f "$work_dir/apk_temp/final/$PowerKeeper" ]; then
    rm -rf $isPowerKeeperDIR/*
    cp -rf $work_dir/apk_temp/final/$PowerKeeper $isPowerKeeperDIR
fi

rm -rf $work_dir/apk_temp
patch "Done"