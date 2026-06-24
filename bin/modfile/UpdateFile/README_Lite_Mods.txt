# DeadZone Lite UpdateFile Mods

Drop the contents of `bin/modfile/UpdateFile` into the same path in the repo.

Files:
- `10_Settings_Lite.sh`: patches `Settings.apk` only.
- `20_SystemUI_Lite.sh`: patches `MiuiSystemUI.apk` only.
- `Lite/Settings_Lite`: Settings assets from Lite package.
- `Lite/SystemUI_Lite`: SystemUI assets from Lite package.

Execution:
- Existing `insupdate.sh` will run these scripts automatically because they are `.sh` files in `bin/modfile/UpdateFile`.
- Each script is independent, so later mods can be added as `11_Settings_*.sh`, `21_SystemUI_*.sh`, etc.

Requirements in build environment:
- `APKEditor.jar` must exist in repo root or inside UpdateFile/Lite.
- Java must be available.

21_SystemUI_VoLTE_CN.sh
- Independent MiuiSystemUI.apk patch.
- OS2/OS3 China ROMs only.
- Finds sget-boolean vX/pX, Lmiui/os/Build;->IS_INTERNATIONAL_BUILD:Z
  in target SystemUI classes and inserts const/4 using the same register.
- Idempotent: skips if the exact const/4 line is already present.
