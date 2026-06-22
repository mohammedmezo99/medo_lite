import os
import sys
import requests
import random
import string

def get_status_info(status):
    status = status.lower()
    if status == 'start': return "🚀", "START BUILD", "Creating the environment..."
    if status == 'sync': return "🔄", "Synchronizing", "Loading source code..."
    if status == 'build': return "🛠️", "CURRENTLY BEING TRANSLATED", "In progress build ROM..."
    if status == 'upload': return "📤", "UPLOADING", "Uploading ROM..."
    if status == 'success': return "✅", "SUCCESS", "The process is complete!"
    if status == 'fail': return "❌", "FAILURE", "An error has occurred!"
    
    # If passing any state not included in the list above.
    return "ℹ️", "UPDATE STATUS", status

def send_notification(status, repo_name, rom_link, channel_id, bot_token, msg_id=None, build_id="Unknown", builder_name="", builder_id=""):
    icon, status_title, status_desc = get_status_info(status)

    # Get GITHUB_RUN_ID to create a link to the Action's log
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if run_id:
        action_url = f"https://github.com/{repo_name}/actions/runs/{run_id}"
    else:
        action_url = f"https://github.com/{repo_name}/actions"

    builder_text = f"👤 *Builder:* {builder_name}\n" if builder_name else ""

    # Read Codename, Version ROM and the Tool version from the file if it exists.
    codename = "Determining..."
    version_rom = "Determining..."
    version_tool = "Determining..."
    
    if os.path.exists("bin/ddevice/device_code.txt"):
        with open("bin/ddevice/device_code.txt", "r", encoding="utf-8") as f:
            codename = f.read().strip()
    elif os.path.exists("bin/ddevice/device_model.txt"):
        with open("bin/ddevice/device_model.txt", "r", encoding="utf-8") as f:
            codename = f.read().strip()
            
    if os.path.exists("bin/ddevice/base_rom_code.txt"):
        with open("bin/ddevice/base_rom_code.txt", "r", encoding="utf-8") as f:
            version_rom = f.read().strip()
    elif os.path.exists("bin/ddevice/base_build_id.txt"):
        with open("bin/ddevice/base_build_id.txt", "r", encoding="utf-8") as f:
            version_rom = f.read().strip()
            
    if os.path.exists("Version"):
        with open("Version", "r", encoding="utf-8") as f:
            version_tool = f.read().strip()

    message = (
        f"{icon} *{status_title}*\n"
        f"━━━━━━━━━━━━━━━━━━\n"
        f"{builder_text}"
        f"📱 *Device (Codename):* `{codename}`\n"
        f"🎯 *Version ROM:* `{version_rom}`\n"
        f"🛠️ *Version Tool:* `{version_tool}`\n"
        f"🚀 *Log build:* [See details here.]({action_url})\n"
        f"📝 *Status:* _{status_desc}_\n"
        f"🔗 *Source:* [Click here to view/download ROM]({rom_link})\n"
        f"🆔 *Build ID:* `{build_id}`\n"
    )

    if msg_id:
        # If we already have the msg_id, we can edit the old message.
        url = f"https://api.telegram.org/bot{bot_token}/editMessageText"
        payload = {
            "chat_id": channel_id,
            "message_id": msg_id,
            "text": message,
            "parse_mode": "Markdown",
            "disable_web_page_preview": True
        }
    else:
        # If we don't have the msg_id yet, send a new message
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        payload = {
            "chat_id": channel_id,
            "text": message,
            "parse_mode": "Markdown",
            "disable_web_page_preview": True
        }

    try:
        response = requests.post(url, json=payload)
        response.raise_for_status()
        res_data = response.json()
        
        # Get the message_id of the message just sent.
        new_msg_id = res_data.get('result', {}).get('message_id')
        
        # Write message_id to the GitHub Actions environment variable for reuse in subsequent steps
        if not msg_id and new_msg_id and "GITHUB_ENV" in os.environ:
            with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as f:
                f.write(f"TELEGRAM_MSG_ID={new_msg_id}\n")
            print(f"Saved TELEGRAM_MSG_ID={new_msg_id} to GITHUB_ENV for automatic message update.")
            
        print("Notification sent/updated to the channel successfully.!")
        # Send a private message (PM) to the build person if the status is success or failure.
        if status.lower() in ['success', 'fail'] and builder_id:
            pm_url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
            
            if status.lower() == 'success':
                pm_text = (
                    f"🎉 *BUILD ROM REQUEST COMPLETED!*\n\n"
                    f"{message}\n"
                    f"⬇️ *Download ROM at:* [https://nothingsvn.vercel.app/](https://nothingsvn.vercel.app/)"
                )
            else:
                pm_text = (
                    f"⚠️ *BUILD ROM REQUEST FAILED!*\n\n"
                    f"{message}\n"
                    f"💡 *Suggestions:* Please click the build log link above to view the detailed error."
                )
                
            pm_payload = {
                "chat_id": builder_id,
                "text": pm_text,
                "parse_mode": "Markdown",
                "disable_web_page_preview": True
            }
            try:
                requests.post(pm_url, json=pm_payload)
                print(f"Notification sent successfully to user {builder_id}")
            except Exception as e:
                print(f"Private message sending error: {e}")

    except Exception as e:
        print(f"Error occurred while sending notification: {e}")
        if 'response' in locals():
            print(response.text)

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python notify.py <status> <repo_name> <rom_link> [prefix_id] [builder_name] [builder_id]")
        sys.exit(1)

    status = sys.argv[1]
    repo_name = sys.argv[2]
    rom_link = sys.argv[3]
    
    # Prefix for build ID (e.g., xiaomi, xst, oplus))
    prefix = sys.argv[4] if len(sys.argv) > 4 else "build"
    
    # Information about the builder
    builder_name = sys.argv[5] if len(sys.argv) > 5 else ""
    builder_id = sys.argv[6] if len(sys.argv) > 6 else ""
    
    # Get token, channel ID, message ID and Build ID from environment variables
    bot_token = os.environ.get("TELEGRAM_BOT_TOKEN")
    channel_id = os.environ.get("TELEGRAM_CHANNEL_ID")
    msg_id = os.environ.get("TELEGRAM_MSG_ID") 
    build_id = os.environ.get("TELEGRAM_BUILD_ID")

    # Create new Build ID if not exists
    if not build_id:
        random_digits = ''.join(random.choices(string.digits, k=8))
        build_id = f"{prefix}_{random_digits}"
        
        # Save it to GITHUB_ENV for use in subsequent steps.
        if "GITHUB_ENV" in os.environ:
            with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as f:
                f.write(f"TELEGRAM_BUILD_ID={build_id}\n")

    if not bot_token or not channel_id:
        print("Error: Missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHANNEL_ID in environment variables.")
        sys.exit(1)

    send_notification(status, repo_name, rom_link, channel_id, bot_token, msg_id, build_id, builder_name, builder_id)
