work_dir=$(pwd) 
source $work_dir/functions.sh
product="$work_dir/build/baserom/images/product"
regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)

if [[ $regionTYPE == *"Global"* ]]; then
    mods "Disable POCO Theme"
    rm -rf "$product/media/theme/default/icons"
    rm -rf "$product/media/theme/default/dynamicicons"s
    cp -rf "$work_dir/bin/modfile/UpdateFile/Global_POCO2Xiaomi-Icon/icons" "$product/media/theme/default"
    cp -rf "$work_dir/bin/modfile/UpdateFile/Global_POCO2Xiaomi-Icon/dynamicicons" "$product/media/theme/default"
    mods "Done"
fi