#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

ROOT = Path.cwd()

DATA_FILES = [
    ROOT / "bin/ddevice/data/deadzone_devices.json",
    ROOT / "bin/ddevice/data/devices.json",
    ROOT / "bin/ddevice/data/names.json",
]

REGION_SUFFIXES = [
    "eeaglobal",
    "europeglobal",
    "indiaglobal",
    "inglobal",
    "indonesiaglobal",
    "idglobal",
    "russiaglobal",
    "ruglobal",
    "taiwanglobal",
    "twglobal",
    "turkeyglobal",
    "trglobal",
    "japanglobal",
    "jpglobal",
    "global",
    "china",
    "cn",
]

BAD_VALUES = {
    "",
    "null",
    "none",
    "unknown",
    "unknown xiaomi device",
    "not found",
    "key not found",
    "device not found",
}

def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig").replace("\x00", "").strip()
    except Exception:
        return ""

def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text((value or "").strip() + "\n", encoding="utf-8")

def normalize_token(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (value or "").strip().lower())

def clean_base_codename(value: str) -> str:
    token = normalize_token(value)

    for suffix in REGION_SUFFIXES:
        if token.endswith(suffix):
            token = token[: -len(suffix)]
            break

    return token or "unknown"

def is_bad(value: str) -> bool:
    text = (value or "").strip()
    lowered = text.lower()
    return lowered in BAD_VALUES or "not found" in lowered or "không tìm thấy" in lowered

def load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def lookup_device_name(base_codename: str, raw_code: str) -> str:
    lookup_keys = {
        normalize_token(base_codename),
        normalize_token(raw_code),
        clean_base_codename(raw_code),
    }

    for data_file in DATA_FILES:
        data = load_json(data_file)
        for key, value in data.items():
            normalized_key = clean_base_codename(str(key))
            if normalized_key in lookup_keys:
                name = str(value).strip()
                if not is_bad(name):
                    return name

    if base_codename and base_codename != "unknown":
        return f"Xiaomi {base_codename.upper()}"

    return "Unknown Xiaomi Device"

def main() -> int:
    arg = sys.argv[1].strip() if len(sys.argv) > 1 else ""

    file_key = read_text(ROOT / "bin/ddevice/device_f.txt")
    file_code = read_text(ROOT / "bin/ddevice/device_code.txt")

    raw = arg or file_key or file_code
    base_codename = clean_base_codename(raw)
    device_name = lookup_device_name(base_codename, raw or file_code)

    write_text(ROOT / "bin/ddevice/codename.txt", base_codename)
    write_text(ROOT / "bin/ddevice/device_f.txt", base_codename)
    write_text(ROOT / "bin/ddevice/name_devices.txt", device_name)
    write_text(ROOT / "bin/ddevice/device_name.txt", device_name)

    if not file_code:
        write_text(ROOT / "bin/ddevice/device_code.txt", base_codename.upper())

    print(f"[INFO] - Device Codename: {base_codename}")
    print(f"[INFO] - Device Name: {device_name}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
