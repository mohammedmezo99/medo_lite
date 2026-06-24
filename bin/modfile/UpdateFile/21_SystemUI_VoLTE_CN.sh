#!/usr/bin/env bash
# SystemUI VoLTE CN mod for DeadZone/MEZO UpdateFile pipeline.
# Independent script: patches MiuiSystemUI.apk only.
# Goal: Hide 4G icon and show VoLTE on Statusbar for OS2/OS3 China ROMs.
set -euo pipefail

work_dir="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$work_dir/tmp/systemui_volte_cn_$$"
APK_NAME="MiuiSystemUI.apk"
SRC_NAME="MiuiSystemUI_apk_src"
FRAMEWORK_VERSION="35"

if [[ -f "$work_dir/functions.sh" ]]; then
    # shellcheck disable=SC1091
    source "$work_dir/functions.sh"
fi

mod_log() {
    if declare -F mods >/dev/null 2>&1; then
        mods "[SystemUI VoLTE CN] $1"
    else
        echo "[SystemUI VoLTE CN] $1"
    fi
}

mod_warn() {
    if declare -F warn >/dev/null 2>&1; then
        warn "[SystemUI VoLTE CN] $1"
    else
        echo "[SystemUI VoLTE CN][WARN] $1"
    fi
}

cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

find_apk_editor() {
    local candidate
    for candidate in \
        "$work_dir/APKEditor.jar" \
        "$SCRIPT_DIR/APKEditor.jar" \
        "$SCRIPT_DIR/Lite/APKEditor.jar"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    candidate="$(find "$work_dir" -maxdepth 5 -type f -name 'APKEditor.jar' 2>/dev/null | head -n 1 || true)"
    if [[ -n "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi
    return 1
}

find_target_apk() {
    local base="$work_dir/build/baserom/images"
    [[ -d "$base" ]] || return 1
    find "$base" -type f -name "$APK_NAME" 2>/dev/null \
        | awk '
            /system_ext/ {print "0 " $0; next}
            /product/ {print "1 " $0; next}
            /system/ {print "2 " $0; next}
            {print "9 " $0}
        ' \
        | sort \
        | sed 's/^[0-9] //g' \
        | head -n 1
}

rom_os="$(cat "$work_dir/bin/ddevice/rom_os.txt" 2>/dev/null || true)"
region_type="$(cat "$work_dir/bin/ddevice/device_type.txt" 2>/dev/null || true)"

if [[ "$rom_os" != "OS2" && "$rom_os" != "OS3" ]]; then
    mod_log "Skip: target is OS2/OS3 only. Current ROM OS: ${rom_os:-unknown}"
    exit 0
fi

if [[ "$region_type" != "China" ]]; then
    mod_log "Skip: target is China ROM only. Current region: ${region_type:-unknown}"
    exit 0
fi

if ! command -v java >/dev/null 2>&1; then
    mod_warn "Java not found; skipping."
    exit 0
fi

APK_EDITOR="$(find_apk_editor || true)"
if [[ -z "$APK_EDITOR" ]]; then
    mod_warn "APKEditor.jar not found; skipping."
    exit 0
fi

TARGET_APK="$(find_target_apk || true)"
if [[ -z "$TARGET_APK" || ! -f "$TARGET_APK" ]]; then
    mod_warn "MiuiSystemUI.apk not found under build/baserom/images; skipping."
    exit 0
fi

mod_log "Target: $TARGET_APK"
mkdir -p "$TMP_DIR"
WORK_APK="$TMP_DIR/$APK_NAME"
SRC_DIR="$TMP_DIR/$SRC_NAME"
OUT_APK="$TMP_DIR/${APK_NAME%.apk}_volte_cn.apk"

cp -f "$TARGET_APK" "$WORK_APK"

mod_log "Decompiling MiuiSystemUI.apk"
rm -rf "$SRC_DIR"
java -jar "$APK_EDITOR" d -framework-version "$FRAMEWORK_VERSION" -i "$WORK_APK" -o "$SRC_DIR"

python3 - "$SRC_DIR" <<'PY'
from __future__ import annotations

from pathlib import Path
import re
import sys

src_dir = Path(sys.argv[1])

# Class paths inside MiuiSystemUI apk source. APKEditor may place them under smali/classes*,
# so we search by the relative class path instead of hardcoding classes folder number.
target_classes = [
    "com/android/systemui/MiuiOperatorCustomizedPolicy.smali",
    "com/android/systemui/statusbar/policy/MiuiCarrierTextController.smali",
    "com/android/systemui/statusbar/pipeline/mobile/ui/viewmodel/MiuiCellularIconVM$special$$inlined$combine$1$3.smali",
    "com/android/systemui/statusbar/pipeline/mobile/ui/binder/MiuiMobileIconBinder$bind$1$1$10.smali",
]

# Capture the exact destination register from the sget-boolean line.
# Example:
#   sget-boolean v0, Lmiui/os/Build;->IS_INTERNATIONAL_BUILD:Z
# Insert below:
#   const/4 v0, 0x1
sget_re = re.compile(
    r"^(?P<indent>\s*)sget-boolean\s+(?P<reg>[vp]\d+),\s*"
    r"Lmiui/os/Build;->IS_INTERNATIONAL_BUILD:Z\s*$"
)


def log(msg: str) -> None:
    print(f"[SystemUI VoLTE CN] {msg}")


def patch_file(path: Path) -> int:
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines(keepends=True)
    out: list[str] = []
    patch_count = 0
    i = 0

    while i < len(lines):
        line = lines[i]
        out.append(line)
        match = sget_re.match(line.rstrip("\r\n"))
        if not match:
            i += 1
            continue

        reg = match.group("reg")
        indent = match.group("indent")
        inserted_line = f"{indent}const/4 {reg}, 0x1\n"

        # Idempotency guard: skip if the same register is already forced true right after it.
        already_patched = False
        for next_line in lines[i + 1 : min(i + 5, len(lines))]:
            stripped = next_line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if stripped == f"const/4 {reg}, 0x1":
                already_patched = True
            break

        if not already_patched:
            out.append(inserted_line)
            patch_count += 1

        i += 1

    if patch_count:
        path.write_text("".join(out), encoding="utf-8")

    return patch_count


total = 0
found_files = 0
missing: list[str] = []

for rel in target_classes:
    matches = sorted(src_dir.glob(f"smali*/**/{rel}"))
    if not matches:
        missing.append(rel)
        continue

    for path in matches:
        found_files += 1
        count = patch_file(path)
        total += count
        if count:
            log(f"patched {count} occurrence(s): {path.relative_to(src_dir)}")
        else:
            log(f"already patched or pattern not found: {path.relative_to(src_dir)}")

if missing:
    for rel in missing:
        log(f"missing class: {rel}")

if found_files == 0:
    raise SystemExit("No target SystemUI classes were found; cannot apply VoLTE CN patch.")

if total == 0:
    log("No new changes were needed. Patch is likely already applied or pattern differs.")
else:
    log(f"Total new inserted const/4 lines: {total}")
PY

mod_log "Rebuilding MiuiSystemUI.apk"
rm -f "$OUT_APK"
java -jar "$APK_EDITOR" b -framework-version "$FRAMEWORK_VERSION" -i "$SRC_DIR" -o "$OUT_APK"

if [[ ! -f "$OUT_APK" ]]; then
    mod_warn "Rebuild failed: output APK not created."
    exit 1
fi

OLD_MODE="$(stat -c '%a' "$TARGET_APK" 2>/dev/null || echo 644)"
rm -f "$TARGET_APK"
cp -f "$OUT_APK" "$TARGET_APK"
chmod "$OLD_MODE" "$TARGET_APK" 2>/dev/null || true

mod_log "SystemUI VoLTE CN patch applied successfully."
