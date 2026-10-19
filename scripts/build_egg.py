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

# Build the embedded installer script
installer_script = f"""#!/bin/bash
# ==============================================================================
# BedrockConnect + MCXboxBroadcast Pterodactyl Installer
# Container: ghcr.io/pterodactyl/installers:debian
# Server Mount: /mnt/server
# ==============================================================================
set -e

echo "--------------------------------------------------------"
echo "Installing BedrockConnect + MCXboxBroadcast..."
echo "--------------------------------------------------------"

apt-get update -y
apt-get install -y --no-install-recommends curl jq unzip ca-certificates

cd /mnt/server

mkdir -p bedrockconnect broadcaster

# 1. Write startup supervisor script
cat << 'STARTSH_EOF' > start.sh
{start_sh_content}STARTSH_EOF
chmod +x start.sh

# 2. Seed default BedrockConnect configuration
if [ ! -f "bedrockconnect/serverlist.json" ]; then
    echo "Creating default bedrockconnect/serverlist.json..."
    cat << 'SERVERLIST_EOF' > bedrockconnect/serverlist.json
{default_serverlist}SERVERLIST_EOF
fi

if [ ! -f "bedrockconnect/config.yml" ]; then
    echo "Creating default bedrockconnect/config.yml..."
    cat << 'BCCONFIG_EOF' > bedrockconnect/config.yml
db_type: none
user_servers: true
server_limit: 100
featured_servers: true
kick_inactive: true
custom_servers: serverlist.json
BCCONFIG_EOF
fi

# 3. Seed default MCXboxBroadcast configuration
if [ ! -f "broadcaster/config.yml" ]; then
    echo "Creating default broadcaster/config.yml..."
    cat << 'XBLCONFIG_EOF' > broadcaster/config.yml
{default_config_yml}XBLCONFIG_EOF
fi

# 4. Fetch latest release binaries
BC_JAR="BedrockConnect-1.0-SNAPSHOT.jar"
XBL_JAR="MCXboxBroadcastStandalone.jar"

echo "Checking latest BedrockConnect release..."
BC_TAG=""
BC_LOC=$(curl -sI -m 10 "https://github.com/Pugmatt/BedrockConnect/releases/latest" 2>/dev/null | grep -i "^location:" | tr -d '\\r' | awk '{{print $2}}')
if [ -n "$BC_LOC" ]; then
    BC_TAG=$(basename "$BC_LOC")
fi
[ -z "$BC_TAG" ] && BC_TAG="1.71.0"

echo "Downloading BedrockConnect ${{BC_TAG}}..."
curl -sSL -m 120 -o "bedrockconnect/${{BC_JAR}}" "https://github.com/Pugmatt/BedrockConnect/releases/download/${{BC_TAG}}/${{BC_JAR}}"
echo "$BC_TAG" > .version_bedrockconnect

echo "Checking latest MCXboxBroadcast release..."
XBL_TAG=""
XBL_LOC=$(curl -sI -m 10 "https://github.com/MCXboxBroadcast/Broadcaster/releases/latest" 2>/dev/null | grep -i "^location:" | tr -d '\\r' | awk '{{print $2}}')
if [ -n "$XBL_LOC" ]; then
    XBL_TAG=$(basename "$XBL_LOC")
fi
[ -z "$XBL_TAG" ] && XBL_TAG="159"

echo "Downloading MCXboxBroadcast ${{XBL_TAG}}..."
curl -sSL -m 120 -o "broadcaster/${{XBL_JAR}}" "https://github.com/MCXboxBroadcast/Broadcaster/releases/download/${{XBL_TAG}}/${{XBL_JAR}}"
echo "$XBL_TAG" > .version_broadcaster

echo "--------------------------------------------------------"
echo "Installation completed successfully!"
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
    "startup": "bash start.sh",
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
