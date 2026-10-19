#!/bin/bash
# ==============================================================================
# BedrockConnect + MCXboxBroadcast Egg Installer
# Environment: ghcr.io/pterodactyl/installers:debian
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

BC_JAR="BedrockConnect-1.0-SNAPSHOT.jar"
XBL_JAR="MCXboxBroadcastStandalone.jar"

# 1. Fetch latest BedrockConnect
echo "Fetching latest release tag for Pugmatt/BedrockConnect..."
BC_TAG=""
BC_LOC=$(curl -sI -m 10 "https://github.com/Pugmatt/BedrockConnect/releases/latest" 2>/dev/null | grep -i "^location:" | tr -d '\r' | awk '{print $2}')
if [ -n "$BC_LOC" ]; then
    BC_TAG=$(basename "$BC_LOC")
fi
[ -z "$BC_TAG" ] && BC_TAG="1.71.0"

echo "Downloading BedrockConnect (${BC_TAG})..."
curl -sSL -m 120 -o "bedrockconnect/${BC_JAR}" "https://github.com/Pugmatt/BedrockConnect/releases/download/${BC_TAG}/${BC_JAR}"
echo "$BC_TAG" > .version_bedrockconnect

# 2. Fetch latest MCXboxBroadcast
echo "Fetching latest release tag for MCXboxBroadcast/Broadcaster..."
XBL_TAG=""
XBL_LOC=$(curl -sI -m 10 "https://github.com/MCXboxBroadcast/Broadcaster/releases/latest" 2>/dev/null | grep -i "^location:" | tr -d '\r' | awk '{print $2}')
if [ -n "$XBL_LOC" ]; then
    XBL_TAG=$(basename "$XBL_LOC")
fi
[ -z "$XBL_TAG" ] && XBL_TAG="159"

echo "Downloading MCXboxBroadcast (${XBL_TAG})..."
curl -sSL -m 120 -o "broadcaster/${XBL_JAR}" "https://github.com/MCXboxBroadcast/Broadcaster/releases/download/${XBL_TAG}/${XBL_JAR}"
echo "$XBL_TAG" > .version_broadcaster

# 3. Create default BedrockConnect configuration & server list if not already present
if [ ! -f "bedrockconnect/serverlist.json" ]; then
    echo "Creating default serverlist.json..."
    cat << 'EOF' > bedrockconnect/serverlist.json
[
  {
    "name": "Featured: The Hive",
    "iconUrl": "",
    "address": "geo.hivebedrock.network",
    "port": 19132
  },
  {
    "name": "Featured: CubeCraft",
    "iconUrl": "",
    "address": "mco.cubecraft.net",
    "port": 19132
  },
  {
    "name": "Example: My Dedicated Server",
    "iconUrl": "",
    "address": "play.example.com",
    "port": 19132
  }
]
EOF
fi

if [ ! -f "bedrockconnect/config.yml" ]; then
    echo "Creating default BedrockConnect config.yml..."
    cat << 'EOF' > bedrockconnect/config.yml
db_type: none
user_servers: true
server_limit: 100
featured_servers: true
kick_inactive: true
custom_servers: serverlist.json
EOF
fi

# 4. Create default MCXboxBroadcast configuration if not already present
if [ ! -f "broadcaster/config.yml" ]; then
    echo "Creating default MCXboxBroadcast config.yml..."
    cat << 'EOF' > broadcaster/config.yml
# MCXboxBroadcast Standalone Configuration
session:
  update-interval: 30
  query-server: true
  web-query-fallback: true
  config-fallback: true
  session-info:
    host-name: "BedrockConnect Server"
    world-name: "Custom Server Browser"
    game-mode: "Survival"
    players: 0
    max-players: 100
    ip: "auto"
    port: 19132
  ice-port-range:
    min: 0
    max: 0

friend-sync:
  update-interval: 60
  auto-friend: true
  initial-invite: true
  expiry:
    enabled: true
    days: 15
    check: 1800

notifications:
  enabled: false
  webhook-url: ""
  session-expired-message: |
    <!here> Xbox Session expired, sign in again to update it.
    Use the following link to sign in: %s
    Enter the code: %s
  friend-restriction-message: "%s (%s) has restrictions in place that prevent them from being friends with our account."

debug-mode: false
suppress-session-update-message: false
config-version: 5
EOF
fi

# 5. Ensure start.sh exists and is executable
if [ ! -f "start.sh" ]; then
    echo "Error: start.sh was not found in directory. It should be written by the egg definition."
fi
chmod +x start.sh 2>/dev/null || true

echo "--------------------------------------------------------"
echo "Installation complete! Ready to start."
echo "--------------------------------------------------------"
