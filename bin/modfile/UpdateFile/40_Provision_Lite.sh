#!/usr/bin/env bash
# Provision Lite mod for DeadZone/MEZO UpdateFile pipeline.
# Independent script: only patches Provision.apk strings.
# Target path priority: system_ext/priv-app/Provision.apk
set -euo pipefail

work_dir="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$work_dir/tmp/provision_lite_$$"
APK_NAME="Provision.apk"
SRC_NAME="Provision_apk_src"
FRAMEWORK_VERSION="35"

if [[ -f "$work_dir/functions.sh" ]]; then
    # shellcheck disable=SC1091
    source "$work_dir/functions.sh"
fi

mod_log() {
    if declare -F mods >/dev/null 2>&1; then
        mods "[Provision Lite] $1"
    else
        echo "[Provision Lite] $1"
    fi
}

mod_warn() {
    if declare -F warn >/dev/null 2>&1; then
        warn "[Provision Lite] $1"
    else
        echo "[Provision Lite][WARN] $1"
    fi
}

cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

find_apk_editor() {
    local candidate="$work_dir/bin/apktool/APKEditor.jar"
    if [[ -f "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi
    return 1
}

find_target_apk() {
    local base="$work_dir/build/baserom/images"
    [[ -d "$base" ]] || return 1

    # Prefer Provision.apk inside system_ext/priv-app exactly, then any system_ext path.
    find "$base" -type f -name "$APK_NAME" 2>/dev/null \
        | awk '
            /system_ext.*priv-app/ {print "0 " $0; next}
            /system_ext/ {print "1 " $0; next}
            /system.*priv-app/ {print "2 " $0; next}
            /product.*priv-app/ {print "3 " $0; next}
            {print "9 " $0}
        ' \
        | sort \
        | sed 's/^[0-9] //g' \
        | head -n 1
}

if ! command -v java >/dev/null 2>&1; then
    mod_warn "Java not found; skipping Provision Lite."
    exit 0
fi

APK_EDITOR="$(find_apk_editor || true)"
if [[ -z "$APK_EDITOR" ]]; then
    mod_warn "APKEditor.jar not found; skipping Provision Lite."
    exit 0
fi

TARGET_APK="$(find_target_apk || true)"
if [[ -z "$TARGET_APK" || ! -f "$TARGET_APK" ]]; then
    mod_warn "Provision.apk not found under build/baserom/images; skipping."
    exit 0
fi

if [[ "$TARGET_APK" != *"system_ext"* || "$TARGET_APK" != *"priv-app"* ]]; then
    mod_warn "Provision.apk found outside expected system_ext/priv-app path: $TARGET_APK"
fi

mod_log "Target: $TARGET_APK"
mkdir -p "$TMP_DIR"
WORK_APK="$TMP_DIR/$APK_NAME"
SRC_DIR="$TMP_DIR/$SRC_NAME"
OUT_APK="$TMP_DIR/${APK_NAME%.apk}_lite.apk"

cp -f "$TARGET_APK" "$WORK_APK"

mod_log "Decompiling Provision.apk"
rm -rf "$SRC_DIR"
java -jar "$APK_EDITOR" d -framework-version "$FRAMEWORK_VERSION" -i "$WORK_APK" -o "$SRC_DIR"

python3 - "$SRC_DIR" <<'PY'
from __future__ import annotations

from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

src_dir = Path(sys.argv[1])

# Exact values requested for Provision strings.
STARTUP_TEXT = "Lets rock with MEZO Development Project"
COMPLETE_TEXT = "Ready to Rock with DeadZoneROM!"

# Exact names + pattern-based fallback for similar names.
EXACT_REPLACEMENTS = {
    "miui14_global_start_up_slogan": STARTUP_TEXT,
    "miui14_start_up_slogan": STARTUP_TEXT,
    "provision_complete_text": COMPLETE_TEXT,
}

STARTUP_NAME_RE = re.compile(r"(^|_)(global_)?start_up_slogan$|miui\d+.*start_up_slogan", re.I)
COMPLETE_NAME_RE = re.compile(r"provision.*complete.*text", re.I)


def log(msg: str) -> None:
    print(f"[Provision Lite] {msg}")


def replacement_for(name: str) -> str | None:
    if name in EXACT_REPLACEMENTS:
        return EXACT_REPLACEMENTS[name]
    if STARTUP_NAME_RE.search(name):
        return STARTUP_TEXT
    if COMPLETE_NAME_RE.search(name):
        return COMPLETE_TEXT
    return None


def candidate_strings_files(root: Path) -> list[Path]:
    files: list[Path] = []
    # APKEditor usually outputs resources/package_*/res/values*/strings.xml.
    files.extend(root.glob("resources/*/res/values*/strings.xml"))
    files.extend(root.glob("res/values*/strings.xml"))
    # Fallback for unusual layouts.
    files.extend(root.rglob("values*/strings.xml"))

    seen: set[str] = set()
    unique: list[Path] = []
    for path in files:
        key = str(path.resolve())
        if key in seen or not path.is_file():
            continue
        seen.add(key)
        unique.append(path)
    return unique


def patch_xml_file(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="ignore")
    try:
        root = ET.fromstring(text)
    except ET.ParseError as exc:
        log(f"skip invalid XML {path.relative_to(src_dir)}: {exc}")
        return 0

    changed = 0
    for elem in root.iter("string"):
        name = elem.attrib.get("name", "")
        new_value = replacement_for(name)
        if new_value is None:
            continue
        if elem.text == new_value:
            continue
        elem.text = new_value
        changed += 1

    if not changed:
        return 0

    # Preserve a normal Android resource XML shape. APKEditor accepts this format.
    ET.indent(root, space="    ")
    new_text = ET.tostring(root, encoding="unicode", short_empty_elements=False)
    if not new_text.startswith("<?xml"):
        new_text = '<?xml version="1.0" encoding="utf-8"?>\n' + new_text
    path.write_text(new_text + "\n", encoding="utf-8")
    return changed


strings_files = candidate_strings_files(src_dir)
if not strings_files:
    raise SystemExit("No strings.xml files found inside decompiled Provision.apk")

total = 0
for strings_xml in strings_files:
    count = patch_xml_file(strings_xml)
    total += count
    if count:
        log(f"patched {count} string(s): {strings_xml.relative_to(src_dir)}")

if total == 0:
    log("No Provision strings changed. They may already be patched or names differ.")
else:
    log(f"Total patched Provision strings: {total}")
PY

mod_log "Rebuilding Provision.apk"
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

mod_log "Provision Lite strings patch applied successfully."

