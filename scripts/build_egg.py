#!/usr/bin/env python3
"""
Generator script to compile the Pterodactyl Egg JSON.
Bundles scripts/start.sh, defaults, and egg metadata into egg-bedrockconnect-xboxbroadcast.json.
"""
import json
import os
from datetime import datetime

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.join(ROOT_DIR, "scripts")
DEFAULTS_DIR = os.path.join(ROOT_DIR, "defaults")

with open(os.path.join(SCRIPTS_DIR, "start.sh"), "r", encoding="utf-8") as f:
    start_sh_content = f.read()

with open(os.path.join(DEFAULTS_DIR, "serverlist.json"), "r", encoding="utf-8") as f:
    default_serverlist = f.read()

with open(os.path.join(DEFAULTS_DIR, "config.yml.template"), "r", encoding="utf-8") as f:
    default_config_yml = f.read()

# Build the embedded instant installer script (zero package managers, zero pre-downloads)
installer_script = f"""#!/bin/bash
# ==============================================================================
# BedrockConnect + MCXboxBroadcast Instant Installer
# Container: ghcr.io/pterodactyl/installers:debian
# Server Mount: /mnt/server
# ==============================================================================
set -e

echo "--------------------------------------------------------"
echo "Setting up BedrockConnect + MCXboxBroadcast supervisor..."
echo "--------------------------------------------------------"

cd /mnt/server

# Write the supervisor script directly to server root
cat << 'STARTSH_EOF' > start.sh
{start_sh_content}STARTSH_EOF
chmod +x start.sh

echo "--------------------------------------------------------"
echo "Installation completed in < 0.2s!"
echo "Binaries and configs will be automatically fetched on container start."
echo "--------------------------------------------------------"
"""

egg_data = {
    "_comment": "DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL - PTERODACTYL.IO",
    "meta": {
        "version": "PTDL_v2",
        "update_url": "https://github.com/woliver99/bedrock-connecter/releases/latest/download/egg-bedrockconnect-xboxbroadcast.json"
    },
    "exported_at": datetime.now().astimezone().isoformat(),
    "name": "BedrockConnect + MCXboxBroadcast",
    "author": "support@pterodactyl.io",
    "description": (
        "All-in-one low-maintenance Minecraft Bedrock server gateway combining BedrockConnect and MCXboxBroadcast. "
        "Allows console players (Xbox, PlayStation, Nintendo Switch) to join custom servers via Xbox Live Friends "
        "and access a custom server list. Features an autonomous background supervisor that monitors process health, "
        "periodically checks for upstream GitHub releases, verifies downloads, and performs zero-maintenance rolling restarts."
    ),
    "features": None,
    "docker_images": {
        "Custom GHCR Image (woliver99)": "ghcr.io/woliver99/bedrock-connecter:latest",
        "Java 21 (Recommended)": "ghcr.io/ptero-eggs/yolks:java_21",
        "Java 17": "ghcr.io/ptero-eggs/yolks:java_17",
        "Pterodactyl Java 21": "ghcr.io/pterodactyl/yolks:java_21"
    },
    "file_denylist": [],
    "startup": "if [ ! -f start.sh ]; then curl -sSL -o start.sh https://raw.githubusercontent.com/woliver99/bedrock-connecter/main/scripts/start.sh && chmod +x start.sh; fi; bash start.sh",
    "config": {
        "files": "{}",
        "startup": json.dumps({"done": "Both BedrockConnect and MCXboxBroadcast are running!"}, indent=4),
        "logs": "{}",
        "stop": "stop"
    },
    "scripts": {
        "installation": {
            "script": installer_script,
            "container": "ghcr.io/pterodactyl/installers:debian",
            "entrypoint": "bash"
        }
    },
    "variables": [
        {
            "name": "Update Check Interval (Minutes)",
            "description": "How frequently in minutes the supervisor polls GitHub for new BedrockConnect and MCXboxBroadcast releases. Minimum is 5 minutes.",
            "env_variable": "UPDATE_CHECK_INTERVAL",
            "default_value": "60",
            "user_viewable": True,
            "user_editable": True,
            "rules": "required|numeric|min:5",
            "field_type": "text"
        },
        {
            "name": "Auto-Update Restart",
            "description": "Whether to perform an immediate in-container graceful restart when an update is verified and installed (true), or wait for the next manual reboot (false).",
            "env_variable": "AUTO_UPDATE_RESTART",
            "default_value": "true",
            "user_viewable": True,
            "user_editable": True,
            "rules": "required|string|in:true,false",
            "field_type": "text"
        },
        {
            "name": "GitHub Personal Access Token",
            "description": "Optional GitHub PAT to prevent rate-limiting when checking updates if your host machine shares a public IP with many services.",
            "env_variable": "GITHUB_TOKEN",
            "default_value": "",
            "user_viewable": True,
            "user_editable": True,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "BedrockConnect Memory (MB)",
            "description": "Maximum RAM (heap memory) in megabytes allocated to the BedrockConnect Java process.",
            "env_variable": "JAVA_MEMORY_BC",
            "default_value": "256",
            "user_viewable": True,
            "user_editable": True,
            "rules": "required|numeric|min:128",
            "field_type": "text"
        },
        {
            "name": "MCXboxBroadcast Memory (MB)",
            "description": "Maximum RAM (heap memory) in megabytes allocated to the MCXboxBroadcast Java process.",
            "env_variable": "JAVA_MEMORY_XBL",
            "default_value": "256",
            "user_viewable": True,
            "user_editable": True,
            "rules": "required|numeric|min:128",
            "field_type": "text"
        }
    ]
}

target_file = os.path.join(ROOT_DIR, "egg-bedrockconnect-xboxbroadcast.json")
with open(target_file, "w", encoding="utf-8") as f:
    json.dump(egg_data, f, indent=2)

print(f"Successfully generated {target_file}")
