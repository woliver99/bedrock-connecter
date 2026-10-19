#!/bin/bash
# ==============================================================================
# BedrockConnect + MCXboxBroadcast Instant Installer
# Environment: ghcr.io/pterodactyl/installers:debian
# Server Mount: /mnt/server
# ==============================================================================
set -e

echo "--------------------------------------------------------"
echo "Setting up BedrockConnect + MCXboxBroadcast supervisor..."
echo "--------------------------------------------------------"

cd /mnt/server

# If start.sh is provided via egg or script directory, ensure permissions
chmod +x start.sh 2>/dev/null || true

echo "--------------------------------------------------------"
echo "Installation complete! (< 0.2s)"
echo "All binaries and configs will be fetched on container start."
echo "--------------------------------------------------------"
