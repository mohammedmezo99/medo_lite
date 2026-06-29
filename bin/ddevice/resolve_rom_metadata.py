#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path.cwd()
DDIR = ROOT / "bin" / "ddevice"

DEVICE_DATA_FILES = [
    DDIR / "data" / "deadzone_devices.json",
    DDIR / "data" / "devices.json",
    DDIR / "data" / "names.json",
]

DEVICE_KEYS = [
    "ro.product.odm.device",
    "ro.product.vendor.device",
    "ro.product.product.device",
    "ro.product.system.device",
    "ro.product.system_ext.device",
    "ro.product.device",
    "ro.build.product",
]

NAME_KEYS = [
    "ro.product.odm.marketname",
    "ro.product.vendor.marketname",
    "ro.product.product.marketname",
    "ro.product.system.marketname",
    "ro.product.marketname",
    "ro.product.odm.model",
    "ro.product.vendor.model",
    "ro.product.product.model",
    "ro.product.system.model",
    "ro.product.model",
]

ROM_KEYS = [
    "ro.mi.os.version.incremental",
    "ro.build.version.incremental",
]

ANDROID_KEYS = [
    "ro.system.build.version.release",
    "ro.build.version.release",
]

REGION_SUFFIXES = [
    "eeaglobal", "europeglobal",
    "indiaglobal", "inglobal",
    "indonesiaglobal", "idglobal",
    "russiaglobal", "ruglobal",
    "taiwanglobal", "twglobal",
    "turkeyglobal", "trglobal",
    "japanglobal", "jpglobal",
    "global", "china", "cn",
]

def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig", errors="ignore").replace("\x00", "").strip()
    except Exception:
        return ""

def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text((value or "").strip() + "\n", encoding="utf-8")

def normalize_token(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (value or "").strip().lower())

def clean_codename(value: str) -> str:
    token = normalize_token(value)
    for suffix in REGION_SUFFIXES:
        if token.endswith(suffix):
            token = token[:-len(suffix)]
            break
    return token or "unknown"

def parse_props(path: Path) -> dict:
    props = {}
    try:
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            props[key.strip()] = value.strip()
    except Exception:
        pass
    return props

def pick(props: dict, keys: list[str]) -> str:
    for key in keys:
        value = props.get(key, "").strip()
        if value:
            return value
    return ""

def load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def lookup_device_name(codename: str) -> str:
    clean = clean_codename(codename)
    for data_file in DEVICE_DATA_FILES:
        for key, value in load_json(data_file).items():
            if clean_codename(str(key)) == clean:
                value = str(value).strip()
                if value and "not found" not in value.lower():
                    return value
    return f"Xiaomi {clean.upper()}" if clean != "unknown" else "Unknown Xiaomi Device"

def find_build_props() -> list[Path]:
    roots = [
        ROOT / "build" / "baserom" / "images",
        ROOT / "build" / "baserom",
    ]
    found = []
    seen = set()
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("build.prop"):
            s = str(path)
            if s not in seen:
                seen.add(s)
                found.append(path)
    return found

def main() -> int:
    combined = {}

    for prop_path in find_build_props():
        props = parse_props(prop_path)
        for key, value in props.items():
            if key not in combined and value:
                combined[key] = value

    old_device_code = read_text(DDIR / "device_code.txt")
    old_device_f = read_text(DDIR / "device_f.txt")
    old_base_rom_code = read_text(DDIR / "base_rom_code.txt")

    codename_raw = pick(combined, DEVICE_KEYS) or old_device_f or old_device_code
    codename = clean_codename(codename_raw)

    market_name = pick(combined, NAME_KEYS)
    resolved_name = market_name or lookup_device_name(codename)

    rom_code = pick(combined, ROM_KEYS) or old_base_rom_code or "Unknown"
    android_release = pick(combined, ANDROID_KEYS)

    write_text(DDIR / "codename.txt", codename)
    write_text(DDIR / "device_f.txt", codename)
    write_text(DDIR / "device_code.txt", codename.upper())
    write_text(DDIR / "name_devices.txt", resolved_name)
    write_text(DDIR / "device_name.txt", resolved_name)

    if rom_code and rom_code != "Unknown":
        write_text(DDIR / "base_rom_code.txt", rom_code)
        write_text(DDIR / "os_code.txt", rom_code)

    if android_release:
        write_text(DDIR / "androidver.txt", android_release)

    print(f"[INFO] - Resolved Codename: {codename}")
    print(f"[INFO] - Resolved Device Name: {resolved_name}")
    print(f"[INFO] - Resolved ROM Code: {rom_code}")
    if android_release:
        print(f"[INFO] - Android Release: {android_release}")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())