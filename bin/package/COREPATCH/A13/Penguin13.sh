dir=$(pwd)
source $dir/functions.sh
penguin_frw="python3 $dir/bin/package/COREPATCH/A13/framework_patch.py"
penguin_srvs="python3 $dir/bin/package/COREPATCH/A13/services_patch.py"
penguin_miui_sv="python3 $dir/bin/package/COREPATCH/A13/miui_service_patch.py"
penguin_miui_frw="python3 $dir/bin/package/COREPATCH/A13/miui_frw_patch.py"
JARDIR="$dir/jar_temp"
repS="python3 $dir/bin/strRep.py"

if [[ ! -d $dir/jar_temp ]]; then

	mkdir $dir/jar_temp
	
fi

get_file_dir() {
	if [[ $1 ]]; then
		sudo find $dir/build/baserom/images/ -name $1 
	else 
		return 0
	fi
}

jar_util() 
{
    cd $dir
    #binary
    if [[ $3 == "fw" ]]; then 
        bak="java -jar $dir/bin/apktool/baksmaliv2.jar d --api 33"
        sma="java -jar $dir/bin/apktool/smaliv2.jar a --api 33"
    fi

    if [[ $1 == "d" ]]; then
        patch "Patching $2 : "

        file_path=$(get_file_dir $2)
        if [[ $file_path ]]; then
            sudo cp "$file_path" $dir/jar_temp
            sudo chown $(whoami) $dir/jar_temp/$2
            unzip $dir/jar_temp/$2 -d $dir/jar_temp/$2.out  >/dev/null 2>&1
            if [[ -d $dir/jar_temp/"$2.out" ]]; then
                rm -rf $dir/jar_temp/$2
                for dex in $(find $dir/jar_temp/"$2.out" -maxdepth 1 -name "*dex" ); do
                    if [[ $4 ]]; then
                        if [[ ! "$dex" == *"$4"* ]]; then
                            $bak $dex -o "$dex.out"
                            [[ -d "$dex.out" ]] && rm -rf $dex
                        fi
                    else
                        $bak $dex -o "$dex.out"
                        [[ -d "$dex.out" ]] && rm -rf $dex        
                    fi
                done
                # # Create necessary directories and copy xBuild.smali
                # mkdir -p $dir/jar_temp/$2.out/classes.dex.out/miuix/os
                # cp $dir/bin/shPlugin/noti/xBuild.smali $dir/jar_temp/$2.out/classes.dex.out/miuix/os/
            fi
        fi
    else 
        if [[ $1 == "a" ]]; then 
            if [[ -d $dir/jar_temp/$2.out ]]; then
                cd $dir/jar_temp/$2.out
                for fld in $(find -maxdepth 1 -name "*.out" ); do
                    if [[ $4 ]]; then
                        if [[ ! "$fld" == *"$4"* ]]; then
                            $sma $fld -o $(echo ${fld//.out})
                            [[ -f $(echo ${fld//.out}) ]] && rm -rf $fld
                        fi
                    else 
                        $sma $fld -o $(echo ${fld//.out})
                        [[ -f $(echo ${fld//.out}) ]] && rm -rf $fld    
                    fi
                done
                7za a -tzip -mx=0 $dir/jar_temp/$2_notal $dir/jar_temp/$2.out/. >/dev/null 2>&1
                #zip -r -j -0 $dir/jar_temp/$2_notal $dir/jar_temp/$2.out/.
                zipalign 4 $dir/jar_temp/$2_notal $dir/jar_temp/$2
                if [[ -f $dir/jar_temp/$2 ]]; then
                    sudo cp -rf $dir/jar_temp/$2 $(get_file_dir $2)
                    patch "$2 Success"
                    rm -rf $dir/jar_temp/$2.out $dir/jar_temp/$2_notal 
                else
                    patch "$2 Fail"
                fi
            fi
        fi
    fi
}

Patch_Framework () {

    jar_util d 'framework.jar' fw 0 10

    $penguin_frw > /dev/null 2>&1
    
    jar_util a 'framework.jar' fw 0 10

    
}

Patch_SV () {
    jar_util d 'services.jar' fw 0 10

    $penguin_srvs > /dev/null 2>&1

    jar_util a 'services.jar' fw 0 10
}

Patch_Miuisv () {
    jar_util d 'miui-services.jar' fw 0 10

    $penguin_miui_sv > /dev/null 2>&1

    jar_util a 'miui-services.jar' fw 0 10
}

Patch_MiuiFramework () {
    jar_util d 'miui-framework.jar' fw 0 10

    $penguin_miui_frw > /dev/null 2>&1

    jar_util a 'miui-framework.jar' fw 0 10
}

Patch_Framework
Patch_SV
Patch_Miuisv
Patch_MiuiFramework