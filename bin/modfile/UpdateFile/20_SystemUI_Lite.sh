#!/usr/bin/env bash
# SystemUI Lite mod for DeadZone/MEZO UpdateFile pipeline.
# Independent script: only patches MiuiSystemUI.apk.
set -euo pipefail

work_dir="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="$SCRIPT_DIR/Lite/SystemUI_Lite"
TMP_DIR="$work_dir/tmp/systemui_lite_$$"
APK_NAME="MiuiSystemUI.apk"
SRC_NAME="MiuiSystemUI_apk_src"
FRAMEWORK_VERSION="35"

if [[ -f "$work_dir/functions.sh" ]]; then
    # shellcheck disable=SC1091
    source "$work_dir/functions.sh"
fi

lite_log() {
    if declare -F mods >/dev/null 2>&1; then
        mods "[SystemUI Lite] $1"
    else
        echo "[SystemUI Lite] $1"
    fi
}

lite_warn() {
    if declare -F warn >/dev/null 2>&1; then
        warn "[SystemUI Lite] $1"
    else
        echo "[SystemUI Lite][WARN] $1"
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
    lite_warn "Java not found; skipping SystemUI Lite."
    exit 0
fi
APK_EDITOR="$(find_apk_editor || true)"
if [[ -z "$APK_EDITOR" ]]; then
    lite_warn "APKEditor.jar not found; skipping SystemUI Lite."
    exit 0
fi
TARGET_APK="$(find_target_apk || true)"
if [[ -z "$TARGET_APK" || ! -f "$TARGET_APK" ]]; then
    lite_warn "MiuiSystemUI.apk not found under build/baserom/images; skipping."
    exit 0
fi
lite_log "Target: $TARGET_APK"
mkdir -p "$TMP_DIR"
WORK_APK="$TMP_DIR/$APK_NAME"
SRC_DIR="$TMP_DIR/$SRC_NAME"
OUT_APK="$TMP_DIR/${APK_NAME%.apk}_patched.apk"
cp -f "$TARGET_APK" "$WORK_APK"
lite_log "Decompiling MiuiSystemUI.apk"
rm -rf "$SRC_DIR"
java -jar "$APK_EDITOR" d -framework-version "$FRAMEWORK_VERSION" -i "$WORK_APK" -o "$SRC_DIR"
python3 - "$SRC_DIR" "$ASSET_DIR" <<'PY'
from pathlib import Path
import re, shutil, sys
src_dir = Path(sys.argv[1])
asset_dir = Path(sys.argv[2])
def log(msg: str) -> None:
    print(f"[SystemUI Lite] {msg}")
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
def ensure_file(path: Path) -> None:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n', encoding='utf-8')
def copy_res_files(res_root: Path) -> None:
    src_res = asset_dir / "res"
    if not src_res.is_dir():
        return
    for path in sorted(src_res.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(src_res)
        dest = res_root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        log(f"copied res/{dest.relative_to(res_root)}")
def parse_drawable_entries(asset_dir: Path) -> list[str]:
    manifest = asset_dir / "res_drawable.txt"
    if not manifest.is_file():
        return []
    text = manifest.read_text(encoding="utf-8", errors="ignore")
    names = re.findall(r'<entry\s+id="0x[0-9a-fA-F]+"\s+name="([^"]+)"\s*/>', text)
    if not names:
        names = re.findall(r'<path\s+name="([^"]+)"', text)
    ordered: list[str] = []
    for name in names:
        if name not in ordered:
            ordered.append(name)
    return ordered
def ensure_public_drawables(public_xml: Path, names: list[str]) -> None:
    if not names:
        log("no drawable entries found in res_drawable.txt")
        return
    ensure_file(public_xml)
    lines = public_xml.read_text(encoding="utf-8", errors="ignore").splitlines(keepends=True)
    existing = set()
    max_id = 0
    public_re = re.compile(r'<public\s+[^>]*type="drawable"[^>]*name="([^"]+)"[^>]*id="(0x[0-9a-fA-F]+)"|<public\s+[^>]*id="(0x[0-9a-fA-F]+)"[^>]*type="drawable"[^>]*name="([^"]+)"')
    for line in lines:
        m = public_re.search(line)
        if not m:
            continue
        if m.group(1):
            name, id_text = m.group(1), m.group(2)
        else:
            id_text, name = m.group(3), m.group(4)
        existing.add(name)
        try:
            max_id = max(max_id, int(id_text, 16))
        except Exception:
            pass
    next_id = max_id + 1 if max_id else 0x7f080000
    insert_lines = []
    for name in names:
        if name in existing:
            continue
        insert_lines.append(f'  <public type="drawable" name="{name}" id="0x{next_id:08x}" />\n')
        next_id += 1
    if not insert_lines:
        log("public.xml already contains SystemUI Lite drawable entries")
        return
    insert_at = len(lines)
    for idx, line in enumerate(lines):
        if "</resources>" in line:
            insert_at = idx
            break
    lines[insert_at:insert_at] = insert_lines
    public_xml.write_text("".join(lines), encoding="utf-8")
    log(f"added {len(insert_lines)} drawable public.xml entries")
res_root = find_res_root(src_dir)
if res_root is None:
    raise SystemExit("Cannot locate APKEditor resource root/public.xml")
log(f"resource root: {res_root}")
copy_res_files(res_root)
ensure_public_drawables(res_root / "values" / "public.xml", parse_drawable_entries(asset_dir))
PY
lite_log "Rebuilding MiuiSystemUI.apk"
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
lite_log "SystemUI Lite applied successfully."

