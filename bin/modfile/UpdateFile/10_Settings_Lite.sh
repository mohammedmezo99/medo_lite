#!/usr/bin/env bash
# Settings Lite mod for DeadZone/MEZO UpdateFile pipeline.
# Independent script: only patches Settings.apk.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ASSET_DIR="$SCRIPT_DIR/Lite/Settings_Lite"
TMP_DIR="$work_dir/tmp/settings_lite_$$"
APK_NAME="Settings.apk"
SRC_NAME="Settings_apk_src"
FRAMEWORK_VERSION="35"

if [[ -f "$work_dir/functions.sh" ]]; then
    # shellcheck disable=SC1091
    source "$work_dir/functions.sh"
fi

lite_log() {
    if declare -F mods >/dev/null 2>&1; then
        mods "[Settings Lite] $1"
    else
        echo "[Settings Lite] $1"
    fi
}

lite_warn() {
    if declare -F warn >/dev/null 2>&1; then
        warn "[Settings Lite] $1"
    else
        echo "[Settings Lite][WARN] $1"
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

if [[ ! -d "$ASSET_DIR" ]]; then
    lite_warn "Missing assets directory: $ASSET_DIR"
    exit 0
fi

if ! command -v java >/dev/null 2>&1; then
    lite_warn "Java not found; skipping Settings Lite."
    exit 0
fi

APK_EDITOR="$(find_apk_editor || true)"
if [[ -z "$APK_EDITOR" ]]; then
    lite_warn "APKEditor.jar not found; skipping Settings Lite."
    exit 0
fi

TARGET_APK="$(find_target_apk || true)"
if [[ -z "$TARGET_APK" || ! -f "$TARGET_APK" ]]; then
    lite_warn "Settings.apk not found under build/baserom/images; skipping."
    exit 0
fi

lite_log "Target: $TARGET_APK"
mkdir -p "$TMP_DIR"
WORK_APK="$TMP_DIR/$APK_NAME"
SRC_DIR="$TMP_DIR/$SRC_NAME"
OUT_APK="$TMP_DIR/${APK_NAME%.apk}_patched.apk"
cp -f "$TARGET_APK" "$WORK_APK"

lite_log "Decompiling Settings.apk"
rm -rf "$SRC_DIR"
java -jar "$APK_EDITOR" d -framework-version "$FRAMEWORK_VERSION" -i "$WORK_APK" -o "$SRC_DIR"

python3 - "$SRC_DIR" "$ASSET_DIR" <<'PY'
from pathlib import Path
import re, shutil, sys, zipfile

src_dir = Path(sys.argv[1])
asset_dir = Path(sys.argv[2])

def log(msg: str) -> None:
    print(f"[Settings Lite] {msg}")

def find_res_root(src: Path) -> Path | None:
    candidates = sorted(src.glob("resources/*/res/values/public.xml"))
    if candidates:
        return candidates[0].parents[1]
    direct_public = src / "res" / "values" / "public.xml"
    if direct_public.is_file():
        return direct_public.parents[1]
    candidates = sorted(src.rglob("values/public.xml"))
    if candidates:
        return candidates[0].parents[1]
    return None

def ensure_file(path: Path, root_tag: str = "resources") -> None:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<{root_tag}>\n</{root_tag}>\n", encoding="utf-8")

def insert_before_end(path: Path, block: str, guard: str) -> bool:
    ensure_file(path)
    text = path.read_text(encoding="utf-8", errors="ignore")
    if guard in text:
        return False
    idx = text.rfind("</resources>")
    if idx == -1:
        text = text.rstrip() + "\n" + block.rstrip() + "\n"
    else:
        text = text[:idx] + block.rstrip() + "\n" + text[idx:]
    path.write_text(text, encoding="utf-8")
    return True

def copy_res_files(res_root: Path) -> None:
    src_res = asset_dir / "res"
    if not src_res.is_dir():
        return
    for path in sorted(src_res.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(src_res)
        dest = res_root / rel
        if dest.suffix.lower() == ".txt":
            dest = dest.with_suffix(".xml")
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        log(f"copied res/{dest.relative_to(res_root)}")

def parse_type_entries(resource_file: Path) -> tuple[str, list[str]] | None:
    resource_type = resource_file.stem.lower()
    text = resource_file.read_text(encoding="utf-8", errors="ignore")
    names = re.findall(r'<entry\s+id="0x[0-9a-fA-F]+"\s+name="([^"]+)"\s*/>', text)
    if not names:
        return None
    return resource_type, names

def ensure_public_entries(public_xml: Path, entries_by_type: dict[str, list[str]]) -> None:
    ensure_file(public_xml)
    lines = public_xml.read_text(encoding="utf-8", errors="ignore").splitlines(keepends=True)
    existing = set()
    max_ids: dict[str, int] = {}
    public_re = re.compile(r'<public\s+[^>]*type="([^"]+)"[^>]*name="([^"]+)"[^>]*id="(0x[0-9a-fA-F]+)"|<public\s+[^>]*id="(0x[0-9a-fA-F]+)"[^>]*type="([^"]+)"[^>]*name="([^"]+)"')
    for line in lines:
        m = public_re.search(line)
        if not m:
            continue
        if m.group(1):
            typ, name, id_text = m.group(1), m.group(2), m.group(3)
        else:
            id_text, typ, name = m.group(4), m.group(5), m.group(6)
        existing.add((typ, name))
        try:
            max_ids[typ] = max(max_ids.get(typ, 0), int(id_text, 16))
        except Exception:
            pass
    insert_lines: list[str] = []
    for typ, names in entries_by_type.items():
        next_id = max_ids.get(typ, 0x7f000000) + 1
        for name in names:
            if (typ, name) in existing:
                continue
            insert_lines.append(f'  <public type="{typ}" name="{name}" id="0x{next_id:08x}" />\n')
            existing.add((typ, name))
            next_id += 1
        max_ids[typ] = next_id - 1
    if not insert_lines:
        log("public.xml already contains Lite entries")
        return
    insert_at = len(lines)
    for idx, line in enumerate(lines):
        if "</resources>" in line:
            insert_at = idx
            break
    lines[insert_at:insert_at] = insert_lines
    public_xml.write_text("".join(lines), encoding="utf-8")
    log(f"added {len(insert_lines)} public.xml entries")

def ensure_values_from_assets(res_root: Path) -> None:
    values = res_root / "values"
    values.mkdir(parents=True, exist_ok=True)
    id_file = asset_dir / "resources" / "id.xml"
    if id_file.is_file():
        ids_xml = values / "ids.xml"
        text = id_file.read_text(encoding="utf-8", errors="ignore")
        for name in re.findall(r'<id\s+name="([^"]+)"\s*/>', text):
            insert_before_end(ids_xml, f'    <item type="id" name="{name}" />\n', f'name="{name}"')
    color_file = asset_dir / "resources" / "color.xml"
    if color_file.is_file():
        colors_xml = values / "colors.xml"
        text = color_file.read_text(encoding="utf-8", errors="ignore")
        for name, value in re.findall(r'<color\s+name="([^"]+)">([^<]+)</color>', text):
            if value.strip().startswith("res/"):
                continue
            insert_before_end(colors_xml, f'    <color name="{name}">{value.strip()}</color>\n', f'name="{name}"')
    string_file = asset_dir / "resources" / "string.xml"
    if string_file.is_file():
        strings_xml = values / "strings.xml"
        text = string_file.read_text(encoding="utf-8", errors="ignore")
        for name, value in re.findall(r'<string\s+name="([^"]+)">(.*?)</string>', text, flags=re.S):
            insert_before_end(strings_xml, f'    <string name="{name}">{value.strip()}</string>\n', f'name="{name}"')
    style_file = asset_dir / "resources" / "style.xml"
    if style_file.is_file():
        styles_xml = values / "styles.xml"
        text = style_file.read_text(encoding="utf-8", errors="ignore")
        for match in re.finditer(r'<style\s+name="([^"]+)".*?</style>', text, flags=re.S):
            name = match.group(1)
            block = "    " + match.group(0).strip().replace("\n", "\n    ") + "\n"
            insert_before_end(styles_xml, block, f'<style name="{name}"')

def add_settings_header(res_root: Path) -> None:
    headers_xml = res_root / "xml" / "settings_headers.xml"
    if not headers_xml.is_file():
        log("settings_headers.xml not found; skipped header injection")
        return
    text = headers_xml.read_text(encoding="utf-8", errors="ignore")
    if "mezo_settings_preference" in text or "MyMezoSettings" in text:
        log("Settings header already exists")
        return
    header = (
        '    <header\n'
        '        android:icon="@drawable/ic_miui_lab_settings"\n'
        '        android:id="@id/mezo_settings_preference"\n'
        '        android:title="@string/mezo"\n'
        '        android:fragment="com.android.settings.MyMezoSettings" />\n'
    )
    lines = text.splitlines(keepends=True)
    insert_at = None
    for idx, line in enumerate(lines):
        if "xiao_mi_hyperos_ai" in line:
            for j in range(idx, min(idx + 12, len(lines))):
                if "/>" in lines[j] or "</header>" in lines[j]:
                    insert_at = j + 1
                    break
            break
    if insert_at is None:
        for idx, line in enumerate(lines):
            if any(tag in line for tag in ("</preference-headers>", "</headers>", "</PreferenceScreen>")):
                insert_at = idx
                break
    if insert_at is None:
        lines.append("\n" + header)
    else:
        lines[insert_at:insert_at] = [header]
    headers_xml.write_text("".join(lines), encoding="utf-8")
    log("added DeadZone/MEZO header to settings_headers.xml")

res_root = find_res_root(src_dir)
if res_root is None:
    raise SystemExit("Cannot locate APKEditor resource root/public.xml")
log(f"resource root: {res_root}")
copy_res_files(res_root)
ensure_values_from_assets(res_root)
entries: dict[str, list[str]] = {}
resources_dir = asset_dir / "resources"
for resource_file in sorted(resources_dir.glob("*.xml")):
    parsed = parse_type_entries(resource_file)
    if not parsed:
        continue
    typ, names = parsed
    entries.setdefault(typ, [])
    for name in names:
        if name not in entries[typ]:
            entries[typ].append(name)
ensure_public_entries(res_root / "values" / "public.xml", entries)
add_settings_header(res_root)
smali_zip = asset_dir / "add_smali" / "smali.zip"
if smali_zip.is_file():
    smali_root = src_dir / "smali" / "classes"
    smali_root.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(smali_zip) as zf:
        zf.extractall(smali_root)
    log(f"extracted Settings smali to {smali_root}")
else:
    log("smali.zip not found; skipped smali injection")
PY

lite_log "Rebuilding Settings.apk"
rm -f "$OUT_APK"
java -jar "$APK_EDITOR" b -framework-version "$FRAMEWORK_VERSION" -i "$SRC_DIR" -o "$OUT_APK"
if [[ ! -f "$OUT_APK" ]]; then
    lite_warn "Rebuild failed: output APK not created."
    exit 1
fi
OLD_MODE="$(stat -c '%a' "$TARGET_APK" 2>/dev/null || echo 644)"
rm -f "$TARGET_APK"
cp -f "$OUT_APK" "$TARGET_APK"
chmod "$OLD_MODE" "$TARGET_APK" 2>/dev/null || true
lite_log "Settings Lite applied successfully."


