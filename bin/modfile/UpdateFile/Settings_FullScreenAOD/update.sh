work_dir=$(pwd)
source $work_dir/functions.sh
rom_os=$(cat $WORK_DIR/bin/ddevice/rom_os.txt)
regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
androidVER=$(cat $WORK_DIR/bin/ddevice/androidver.txt)
FOLDER="$work_dir/build/baserom/images/product/etc/device_features"

if [[ $rom_os == "OS2" || $rom_os == "OS3" ]]; then
  mods "Adding iOS AOD Styes For OS2 & OS3"
  find "$FOLDER" -type f -name "*.xml" -exec sed -i '/<bool name="support_aod">true<\/bool>/a\
  <bool name="is_aod_need_grayscale">false</bool>\
  <bool name="support_aod_fullscreen">true</bool>' {} +
fi