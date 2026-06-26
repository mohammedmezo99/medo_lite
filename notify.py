import html
import json
import os
import re
import sys
import zlib
from datetime import datetime
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parent
TIMEOUT = 30
RELEASE_IMAGE = ROOT / "assets" / "release" / "lite.png"

PRIVATE_STAGE_LABELS = {
    "request_received": "📩 Request received",
    "build_started": "🛠️ Build started",
    "packaging_started": "📦 Packaging started",
    "upload_started": "☁️ Uploading to Google Drive",
    "success": "✅ Build completed",
    "fail": "❌ Build failed",
    "publish_prompt": "📢 Publish decision required",
}

REGION_MAP = {
    "china": "ChinaStable",
    "global": "GlobalStable",
    "eeaglobal": "EEAStable",
    "europe": "EEAStable",
    "inglobal": "IndiaStable",
    "indiaglobal": "IndiaStable",
    "idglobal": "IndonesiaStable",
    "indonesiaglobal": "IndonesiaStable",
    "ruglobal": "RussiaStable",
    "russiaglobal": "RussiaStable",
    "twglobal": "TaiwanStable",
    "taiwanglobal": "TaiwanStable",
    "trglobal": "TurkeyStable",
    "turkeyglobal": "TurkeyStable",
    "jpglobal": "JapanStable",
    "japanglobal": "JapanStable",
}

REGION_BASE_TEXT = {
    "GlobalStable": "Based on pure Global ROM",
    "ChinaStable": "Based on pure China ROM",
    "IndiaStable": "Based on pure Indian ROM",
    "IndonesiaStable": "Based on pure Indonesian ROM",
    "EEAStable": "Based on pure EEA ROM",
    "RussiaStable": "Based on pure Russia ROM",
    "TurkeyStable": "Based on pure Turkey ROM",
    "TaiwanStable": "Based on pure Taiwan ROM",
    "JapanStable": "Based on pure Japan ROM",
}


def read_text(relative_path: str, default: str = "") -> str:
    path = ROOT / relative_path
    if not path.exists():
        return default
    try:
        return path.read_text(encoding="utf-8").strip() or default
    except Exception:
        return default


def write_github_env(name: str, value: str) -> None:
    github_env = os.environ.get("GITHUB_ENV")
    if not github_env or value is None:
        return
    with open(github_env, "a", encoding="utf-8") as handle:
        handle.write(f"{name}={value}\n")


def normalize_android(android_value: str) -> str:
    digits = re.sub(r"[^0-9]", "", android_value or "")
    return f"A{digits}" if digits else "Unknown"


def normalize_region(region_value: str) -> str:
    key = re.sub(r"[^a-z]", "", (region_value or "").strip().lower())
    return REGION_MAP.get(key, region_value or "Unknown")


def clean_codename(raw_codename: str) -> str:
    value = (raw_codename or "").strip().lower()
    if "|" in value:
        value = value.split("|", 1)[0].strip()
    value = re.sub(r"[_-]+", "", value)
    for suffix in (
        "globalstable",
        "chinastable",
        "indiastable",
        "indonesiastable",
        "eeastable",
        "europestable",
        "russiastable",
        "turkeystable",
        "taiwanstable",
        "japanstable",
        "global",
        "china",
        "india",
        "indonesia",
        "eea",
        "europe",
        "russia",
        "turkey",
        "taiwan",
        "japan",
        "stable",
    ):
        if value.endswith(suffix):
            value = value[: -len(suffix)]
            break
    value = re.sub(r"[^a-z0-9]+", "", value)
    return value or "unknown"


def normalize_codename(raw_codename: str) -> str:
    return clean_codename(raw_codename).upper()


def clean_device_name(raw_name: str) -> str:
    parts = [part.strip() for part in (raw_name or "").split("|") if part.strip()]
    unique_parts: list[str] = []
    for part in parts:
        if part not in unique_parts:
            unique_parts.append(part)
    if not unique_parts:
        return "Unknown Xiaomi Device"
    five_g = [part for part in unique_parts if "5G" in part]
    candidates = five_g or unique_parts
    return max(candidates, key=lambda item: (len(item), item))


def build_output_filename(version: str, codename: str, rom_version: str, region: str, android_tag: str) -> str:
    safe_version = (version or "0.00").strip()
    safe_rom_version = (rom_version or "Unknown").strip()
    safe_region = (region or "Unknown").strip()
    safe_android = (android_tag or "Unknown").strip()
    return f"DeadZoneLite_v{safe_version}_{codename}_{safe_rom_version}_{safe_region}-{safe_android}.zip"


def derive_platform(rom_version: str) -> str:
    match = re.match(r"^(OS\d+\.\d+)", (rom_version or "").strip())
    return match.group(1) if match else "Unknown"


def derive_hyperos_major(rom_version: str) -> str:
    match = re.match(r"^OS(\d+)", (rom_version or "").strip())
    return f"HyperOS {match.group(1)}" if match else "HyperOS"


def derive_os_tag(rom_version: str) -> str:
    match = re.match(r"^OS(\d+)", (rom_version or "").strip())
    return f"OS{match.group(1)}" if match else "OS"


def derive_hyperos_tag(rom_version: str) -> str:
    match = re.match(r"^OS(\d+)", (rom_version or "").strip())
    return f"HyperOS{match.group(1)}" if match else "HyperOS"


def derive_android_hash_tag(android_tag: str) -> str:
    digits = re.sub(r"[^0-9]", "", android_tag or "")
    return f"Android{digits}" if digits else "Android"


def safe_link(value: str) -> str:
    return html.escape((value or "").strip(), quote=True)



def load_device_database(relative_path: str) -> dict:
    path = ROOT / relative_path
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def canonical_device_name(codename: str, fallback: str) -> str:
    key = clean_codename(codename).lower()
    fallback = (fallback or "").strip()

    if not key or key == "unknown":
        return fallback or "Unknown Xiaomi Device"

    for relative_path in (
        "bin/ddevice/data/deadzone_devices.json",
        "bin/ddevice/data/devices.json",
        "bin/ddevice/data/names.json",
    ):
        data = load_device_database(relative_path)
        for raw_key, raw_value in data.items():
            if clean_codename(str(raw_key)).lower() == key:
                value = str(raw_value).strip()
                if value and value.lower() not in {"null", "none", "unknown", "unknown xiaomi device"}:
                    return value

    return fallback or f"Xiaomi {key.upper()}"

def get_metadata() -> dict:
    version = read_text("Version", "0.00")
    codename_raw = read_text("bin/ddevice/codename.txt") or read_text("bin/ddevice/device_code.txt")
    codename = normalize_codename(codename_raw)
    rom_version = read_text("bin/ddevice/rom_version.txt") or read_text("bin/ddevice/base_rom_code.txt", "Unknown")
    region = normalize_region(read_text("bin/ddevice/region.txt") or read_text("bin/ddevice/device_type.txt", "Unknown"))
    android = normalize_android(read_text("bin/ddevice/android_version.txt") or read_text("bin/ddevice/androidver.txt", ""))
    platform = read_text("bin/ddevice/platform.txt") or derive_platform(rom_version)
    raw_device_name = clean_device_name(read_text("bin/ddevice/device_name.txt") or read_text("bin/ddevice/name_devices.txt", "Unknown Xiaomi Device"))
    device_name = canonical_device_name(codename, raw_device_name)
    filename = read_text("bin/ddevice/output_zip.txt")
    if not filename:
        filename = build_output_filename(version, codename, rom_version, region, android)
    return {
        "version": version,
        "codename": codename,
        "codename_lower": codename.lower(),
        "rom_version": rom_version,
        "region": region,
        "android": android,
        "android_number": re.sub(r"[^0-9]", "", android),
        "platform": platform,
        "hyperos_major": derive_hyperos_major(rom_version),
        "os_tag": derive_os_tag(rom_version),
        "hyperos_tag": derive_hyperos_tag(rom_version),
        "android_hash_tag": derive_android_hash_tag(android),
        "device_name": device_name or "Unknown Xiaomi Device",
        "filename": filename,
        "drive_link": read_text("bin/ddevice/drive_link.txt"),
        "date": datetime.now().strftime("%d/%m/%Y"),
        "region_base_text": REGION_BASE_TEXT.get(region, "Based on pure official ROM"),
    }


def humanize_stage(stage: str) -> str:
    mapping = {
        "checkout": "Checkout",
        "request_acknowledged": "Request acknowledgement",
        "install_dependencies": "Dependency installation",
        "parse_rom_metadata": "ROM metadata parsing",
        "build": "Build",
        "package": "Packaging",
        "setup_rclone": "Rclone setup",
        "upload_drive": "Google Drive upload",
        "release_post": "Release notification",
        "release_notification": "Release notification",
    }
    return mapping.get((stage or "").strip(), stage or "Unknown")


def format_private_message(status: str, stage: str = "") -> str:
    metadata = get_metadata()
    current_stage = PRIVATE_STAGE_LABELS.get(status, "ℹ️ Status update")
    request_source = (os.environ.get("REQUEST_SOURCE") or "").strip().lower()
    failure_stage = stage or os.environ.get("CURRENT_STAGE", "")

    lines = [
        "🔒 MEZO private live status",
        "",
        f"Current stage: {current_stage}",
        f"Device: {metadata['device_name']}",
        f"Codename: {metadata['codename']}",
        f"ROM version: {metadata['rom_version']}",
        f"Region: {metadata['region']}",
        f"Android: {metadata['android']}",
        f"Filename: {metadata['filename']}",
    ]

    if status == "request_received":
        if request_source.startswith("telegram"):
            lines.append("Source: Telegram")
        else:
            lines.append("Source: Manual GitHub build")
    elif status == "fail":
        lines.append(f"Failed stage: {humanize_stage(failure_stage)}")
        if failure_stage == "release_notification":
            lines.append("Release notification failed.")
            lines.append("Check TELEGRAM_RELEASE_GROUP_ID, TELEGRAM_CHAT_GROUP_ID, and bot admin/send permissions.")
    elif status == "publish_prompt":
        lines.append("Manual GitHub build completed.")
        lines.append("This build was uploaded but not posted publicly.")
        lines.append("Use the buttons below to publish or skip.")

    if metadata["drive_link"]:
        lines.append(f"Drive link: {metadata['drive_link']}")
    elif status in {"upload_started", "success", "publish_prompt"}:
        lines.append("Drive link: Pending")

    if status == "success" and not (request_source.startswith("telegram") or os.environ.get("PUBLISH_RELEASE") == "true"):
        lines.append("Release post: Skipped")
    elif status == "success":
        lines.append("Release post: Automatic")

    return "\n".join(lines)


def format_release_caption() -> str:
    metadata = get_metadata()
    drive_link = metadata["drive_link"].strip()
    if not drive_link:
        raise RuntimeError("Missing Google Drive link")

    version = (metadata["version"] or "").strip()
    if version[:1].lower() == "v":
        version = f"v{version[1:]}"
    elif version:
        version = f"v{version}"

    changelog_link = "https://t.me/DeadZoneCloud/676"
    developer_link = "https://t.me/MohamedMezo1"

    return (
        f"🚀 <b>DeadZone Lite {html.escape(version)} Released</b>\n\n"
        f"📱 <b>Device:</b> {html.escape(metadata['device_name'])}\n"
        f"🧩 <b>Codename:</b> #{html.escape(metadata['codename_lower'])}\n"
        f"⚙️ <b>ROM:</b> {html.escape(metadata['rom_version'])}\n"
        f"🌍 <b>Region:</b> {html.escape(metadata['region'])}\n"
        f"🤖 <b>Android:</b> {html.escape(metadata['android'])}\n\n"
        "━━━━━━━━━━━━━━━\n\n"
        f"📋 <a href=\"{safe_link(changelog_link)}\">Changelogs</a>\n"
        f"👨‍💻 <a href=\"{safe_link(developer_link)}\">Developer MEZO</a>\n\n"
        "━━━━━━━━━━━━━━━\n\n"
        f"⬇️ <b>Download:</b> <a href=\"{safe_link(drive_link)}\">Click Here</a>\n\n"
        "━━━━━━━━━━━━━━━\n"
        f"#{html.escape(metadata['codename_lower'])} #DeadZoneLite "
        f"#{html.escape(metadata['hyperos_tag'])} #{html.escape(metadata['android_hash_tag'])} #MEZO"
    )


def telegram_api_url(method: str) -> str:
    bot_token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not bot_token:
        raise RuntimeError("Missing TELEGRAM_BOT_TOKEN")
    return f"https://api.telegram.org/bot{bot_token}/{method}"


def sync_worker_build_status(status: str) -> None:
    sync_url = (os.environ.get("BUILD_STATUS_WEBHOOK_URL") or "").strip()
    sync_token = (os.environ.get("BUILD_STATUS_WEBHOOK_TOKEN") or "").strip()
    rom_link = (os.environ.get("INPUT_URL") or "").strip()
    if not sync_url or not sync_token or not rom_link:
        return

    metadata = get_metadata()
    payload = {
        "status": status,
        "rom_link": rom_link,
        "builder_id": (os.environ.get("BUILDER_ID") or "").strip(),
        "builder_name": (os.environ.get("BUILDER_NAME") or "").strip(),
        "device_codename": metadata["codename"],
        "device_name": metadata["device_name"],
        "rom_version": metadata["rom_version"],
        "region": metadata["region"],
        "android": metadata["android"],
        "final_zip": metadata["filename"],
        "drive_link": metadata["drive_link"],
    }

    if status == "success" and not payload["drive_link"].strip():
        print("[notify] warning: success sync has empty drive_link; check bin/ddevice/drive_link.txt", file=sys.stderr)

    try:
        response = requests.post(
            sync_url,
            json=payload,
            headers={"Authorization": f"Bearer {sync_token}"},
            timeout=TIMEOUT,
        )
        response.raise_for_status()
    except Exception as exc:
        print(f"[notify] worker sync failed: {exc}", file=sys.stderr)


def send_telegram_message(chat_id: str, text: str, parse_mode: str | None = None) -> int:
    payload = {
        "chat_id": chat_id,
        "text": text,
        "disable_web_page_preview": True,
    }
    if parse_mode:
        payload["parse_mode"] = parse_mode
    response = requests.post(telegram_api_url("sendMessage"), json=payload, timeout=TIMEOUT)
    response.raise_for_status()
    data = response.json()
    if not data.get("ok"):
        raise RuntimeError(f"Telegram sendMessage failed: {data}")
    message_id = data.get("result", {}).get("message_id")
    if message_id is None:
        raise RuntimeError("Telegram sendMessage did not return message_id")
    return int(message_id)


def build_publish_callback_data(action: str, metadata: dict) -> str:
    raw = "|".join(
        [
            (metadata.get("filename") or "").strip().lower(),
            (metadata.get("drive_link") or "").strip().lower(),
            (metadata.get("codename_lower") or "").strip().lower(),
            (metadata.get("rom_version") or "").strip().lower(),
        ]
    )
    token = f"{zlib.crc32(raw.encode('utf-8')) & 0xFFFFFFFF:08x}"
    return f"{action}:{token}"


def send_private_publish_prompt(chat_id: str, text: str, metadata: dict) -> int:
    payload = {
        "chat_id": chat_id,
        "text": text,
        "disable_web_page_preview": True,
        "reply_markup": {
            "inline_keyboard": [
                [
                    {"text": "✅ YES", "callback_data": build_publish_callback_data("dz_publish_yes", metadata)},
                    {"text": "❌ NO", "callback_data": build_publish_callback_data("dz_publish_no", metadata)},
                ]
            ]
        },
    }
    response = requests.post(telegram_api_url("sendMessage"), json=payload, timeout=TIMEOUT)
    response.raise_for_status()
    data = response.json()
    if not data.get("ok"):
        raise RuntimeError(f"Telegram sendMessage failed: {data}")
    message_id = data.get("result", {}).get("message_id")
    if message_id is None:
        raise RuntimeError("Telegram sendMessage did not return message_id")
    return int(message_id)


def edit_telegram_message(chat_id: str, message_id: str, text: str, parse_mode: str | None = None) -> bool:
    payload = {
        "chat_id": chat_id,
        "message_id": int(message_id),
        "text": text,
        "disable_web_page_preview": True,
    }
    if parse_mode:
        payload["parse_mode"] = parse_mode
    response = requests.post(telegram_api_url("editMessageText"), json=payload, timeout=TIMEOUT)
    data = {}
    try:
        data = response.json()
    except Exception:
        data = {}
    if not response.ok:
        description = str(data.get("description", ""))
        if "message is not modified" in description.lower():
            return True
        return False
    return bool(data.get("ok"))


def send_telegram_photo(chat_id: str, caption: str, image_path: Path) -> None:
    with image_path.open("rb") as image_file:
        response = requests.post(
            telegram_api_url("sendPhoto"),
            data={
                "chat_id": chat_id,
                "caption": caption,
                "parse_mode": "HTML",
                "disable_web_page_preview": "true",
            },
            files={"photo": image_file},
            timeout=TIMEOUT,
        )
    response.raise_for_status()


def handle_private(status: str, stage: str = "") -> None:
    chat_id = os.environ.get("MEZO_PRIVATE_CHAT_ID")
    if not chat_id:
        raise RuntimeError("Missing MEZO_PRIVATE_CHAT_ID")

    sync_worker_build_status(status)
    text = format_private_message(status, stage)
    message_id = os.environ.get("MEZO_PRIVATE_MESSAGE_ID", "").strip()
    metadata = get_metadata()

    if status == "publish_prompt":
        new_message_id = send_private_publish_prompt(chat_id, text, metadata)
        write_github_env("MEZO_PRIVATE_MESSAGE_ID", str(new_message_id))
        return

    if status == "request_received" or not message_id:
        new_message_id = send_telegram_message(chat_id, text)
        write_github_env("MEZO_PRIVATE_MESSAGE_ID", str(new_message_id))
        return

    if edit_telegram_message(chat_id, message_id, text):
        write_github_env("MEZO_PRIVATE_MESSAGE_ID", str(message_id))
        return

    new_message_id = send_telegram_message(chat_id, text)
    write_github_env("MEZO_PRIVATE_MESSAGE_ID", str(new_message_id))


def handle_release() -> None:
    chat_id = (os.environ.get("TELEGRAM_RELEASE_GROUP_ID") or "").strip()
    if not chat_id:
        chat_id = (os.environ.get("TELEGRAM_CHAT_GROUP_ID") or "").strip()
    if not chat_id:
        raise RuntimeError("Missing TELEGRAM_RELEASE_GROUP_ID or TELEGRAM_CHAT_GROUP_ID")
    caption = format_release_caption()
    if RELEASE_IMAGE.is_file():
        try:
            send_telegram_photo(chat_id, caption, RELEASE_IMAGE)
            return
        except Exception:
            send_telegram_message(chat_id, caption, parse_mode="HTML")
            return
    send_telegram_message(chat_id, caption, parse_mode="HTML")


def usage() -> str:
    return (
        "Usage:\n"
        "  python notify.py private <request_received|build_started|packaging_started|upload_started|success|fail> [stage]\n"
        "  python notify.py private publish_prompt\n"
        "  python notify.py release success\n"
        "  python notify.py filename\n"
        "  python notify.py build [...legacy-args]"
    )


def main() -> int:
    if len(sys.argv) < 2:
        print(usage())
        return 1

    mode = sys.argv[1].strip().lower()

    if mode == "private":
        if len(sys.argv) < 3:
            print(usage())
            return 1
        status = sys.argv[2].strip().lower()
        stage = sys.argv[3].strip() if len(sys.argv) > 3 else ""
        handle_private(status, stage)
        return 0

    if mode == "release":
        if len(sys.argv) < 3 or sys.argv[2].strip().lower() != "success":
            print(usage())
            return 1
        handle_release()
        return 0

    if mode == "filename":
        metadata = get_metadata()
        print(metadata["filename"])
        write_github_env("FINAL_ROM_FILENAME", metadata["filename"])
        return 0

    if mode == "build":
        handle_private("build_started")
        return 0

    print(usage())
    return 1


if __name__ == "__main__":
    sys.exit(main())
