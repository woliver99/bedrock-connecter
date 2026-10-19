#!/bin/bash
# ==============================================================================
# Pterodactyl & Standalone Docker Container Entrypoint
# ==============================================================================
TZ=${TZ:-UTC}
export TZ

# Determine internal IP route
INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to container workspace
cd /home/container || exit 1

# Print Java environment info
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mjava -version\n"
java -version 2>&1

# Resolve startup command (Pterodactyl passes STARTUP env, Docker passes CLI arguments)
if [ -n "${STARTUP}" ]; then
    STARTUP_CMD="${STARTUP}"
elif [ $# -gt 0 ]; then
    STARTUP_CMD="$*"
else
    STARTUP_CMD="start.sh"
fi

PARSED=$(echo "${STARTUP_CMD}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"
# shellcheck disable=SC2086
exec env ${PARSED}
