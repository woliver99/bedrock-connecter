#!/usr/bin/env bash
# ==============================================================================
# BedrockConnect + MCXboxBroadcast Supervisor & Auto-Updater
# ==============================================================================
set -e

BASE_DIR="/home/container"
BC_DIR="${BASE_DIR}/bedrockconnect"
XBL_DIR="${BASE_DIR}/broadcaster"

BC_JAR="BedrockConnect-1.0-SNAPSHOT.jar"
XBL_JAR="MCXboxBroadcastStandalone.jar"

BC_VER_FILE="${BASE_DIR}/.version_bedrockconnect"
XBL_VER_FILE="${BASE_DIR}/.version_broadcaster"

FIFO_BC="/tmp/bc_${$}.fifo"
FIFO_XBL="/tmp/xbl_${$}.fifo"

# Configuration variables
SERVER_PORT="${SERVER_PORT:-19132}"
JAVA_MEMORY_BC="${JAVA_MEMORY_BC:-256}"
JAVA_MEMORY_XBL="${JAVA_MEMORY_XBL:-256}"
UPDATE_CHECK_INTERVAL="${UPDATE_CHECK_INTERVAL:-60}"
AUTO_UPDATE_RESTART="${AUTO_UPDATE_RESTART:-true}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Enforce minimum update interval of 5 minutes (300 seconds)
if [ "$UPDATE_CHECK_INTERVAL" -lt 5 ] 2>/dev/null; then
    UPDATE_CHECK_INTERVAL=5
fi
CHECK_INTERVAL_SEC=$(( UPDATE_CHECK_INTERVAL * 60 ))

# Process Tracking
BC_PID=""
XBL_PID=""
LOGGER_BC_PID=""
LOGGER_XBL_PID=""
RUNNING=true
UPDATING=false

# ------------------------------------------------------------------------------
# Logging & Helper Functions
# ------------------------------------------------------------------------------
log_info() {
    echo -e "\033[1;36m[BedrockBridge]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_warn() {
    echo -e "\033[1;33m[BedrockBridge:WARN]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "\033[1;31m[BedrockBridge:ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# ------------------------------------------------------------------------------
# Release & Download Helpers
# ------------------------------------------------------------------------------
get_latest_release() {
    local repo="$1"
    local tag=""

    # 1. Zero-rate-limit GitHub 302 redirect inspection
    local location
    location=$(curl -sI -m 8 "https://github.com/${repo}/releases/latest" 2>/dev/null | grep -i "^location:" | tr -d '\r' | awk '{print $2}')
    if [ -n "$location" ]; then
        tag=$(basename "$location")
    fi

    # 2. GitHub REST API fallback
    if [ -z "$tag" ]; then
        local auth_header=()
        if [ -n "$GITHUB_TOKEN" ]; then
            auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
        fi
        tag=$(curl -s -m 8 "${auth_header[@]}" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    fi

    echo "$tag"
}

validate_jar() {
    local file="$1"
    [ ! -f "$file" ] && return 1

    local size
    size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null || echo 0)
    # Ensure binary is at least 500KB
    [ "$size" -lt 500000 ] && return 1

    # Check zip magic bytes 'PK'
    local magic
    magic=$(head -c 2 "$file" 2>/dev/null)
    [ "$magic" != "PK" ] && return 1

    # Verify archive structure with unzip if installed
    if command -v unzip >/dev/null 2>&1; then
        unzip -tq "$file" >/dev/null 2>&1 || return 1
    fi

    return 0
}

download_file() {
    local url="$1"
    local dest="$2"
    local auth_header=()

    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    curl -sSL -m 120 "${auth_header[@]}" -o "$dest" "$url"
}

# ------------------------------------------------------------------------------
# Workspace Initialization
# ------------------------------------------------------------------------------
init_workspace() {
    mkdir -p "$BC_DIR" "$XBL_DIR"

    # Seed BedrockConnect custom server list if missing
    if [ ! -f "${BC_DIR}/serverlist.json" ]; then
        log_info "Initializing default BedrockConnect serverlist.json..."
        cat << 'EOF' > "${BC_DIR}/serverlist.json"
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

    # Seed BedrockConnect config.yml if missing
    if [ ! -f "${BC_DIR}/config.yml" ]; then
        log_info "Initializing default BedrockConnect config.yml..."
        cat << 'EOF' > "${BC_DIR}/config.yml"
db_type: none
user_servers: true
server_limit: 100
featured_servers: true
kick_inactive: true
custom_servers: serverlist.json
EOF
    fi

    # Seed MCXboxBroadcast config.yml if missing
    if [ ! -f "${XBL_DIR}/config.yml" ]; then
        log_info "Initializing default MCXboxBroadcast config.yml..."

        # Attempt to determine public IP
        local detected_ip
        detected_ip=$(curl -s -m 4 https://api.ipify.org 2>/dev/null || echo "")
        if [ -z "$detected_ip" ]; then
            detected_ip="auto"
        fi

        cat << EOF > "${XBL_DIR}/config.yml"
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
    ip: "${detected_ip}"
    port: ${SERVER_PORT}
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

    # Initial JAR acquisition if not present
    if [ ! -f "${BC_DIR}/${BC_JAR}" ]; then
        log_info "Downloading BedrockConnect JAR..."
        local bc_tag
        bc_tag=$(get_latest_release "Pugmatt/BedrockConnect")
        [ -z "$bc_tag" ] && bc_tag="1.71.0"
        download_file "https://github.com/Pugmatt/BedrockConnect/releases/download/${bc_tag}/${BC_JAR}" "${BC_DIR}/${BC_JAR}"
        if validate_jar "${BC_DIR}/${BC_JAR}"; then
            echo "$bc_tag" > "$BC_VER_FILE"
            log_info "BedrockConnect (${bc_tag}) downloaded successfully."
        else
            log_error "BedrockConnect download failed validation! Retrying with fallback tag 1.71.0..."
            download_file "https://github.com/Pugmatt/BedrockConnect/releases/download/1.71.0/${BC_JAR}" "${BC_DIR}/${BC_JAR}"
            echo "1.71.0" > "$BC_VER_FILE"
        fi
    fi

    if [ ! -f "${XBL_DIR}/${XBL_JAR}" ]; then
        log_info "Downloading MCXboxBroadcast JAR..."
        local xbl_tag
        xbl_tag=$(get_latest_release "MCXboxBroadcast/Broadcaster")
        [ -z "$xbl_tag" ] && xbl_tag="159"
        download_file "https://github.com/MCXboxBroadcast/Broadcaster/releases/download/${xbl_tag}/${XBL_JAR}" "${XBL_DIR}/${XBL_JAR}"
        if validate_jar "${XBL_DIR}/${XBL_JAR}"; then
            echo "$xbl_tag" > "$XBL_VER_FILE"
            log_info "MCXboxBroadcast (${xbl_tag}) downloaded successfully."
        else
            log_error "MCXboxBroadcast download failed validation! Retrying with fallback tag 159..."
            download_file "https://github.com/MCXboxBroadcast/Broadcaster/releases/download/159/${XBL_JAR}" "${XBL_DIR}/${XBL_JAR}"
            echo "159" > "$XBL_VER_FILE"
        fi
    fi
}

# ------------------------------------------------------------------------------
# FIFO Log Setup
# ------------------------------------------------------------------------------
setup_fifos() {
    rm -f "$FIFO_BC" "$FIFO_XBL"
    mkfifo "$FIFO_BC" "$FIFO_XBL"

    # BedrockConnect Logger
    (
        while [ "$RUNNING" = true ]; do
            while IFS= read -r line; do
                echo -e "\033[0;32m[BedrockConnect]\033[0m $line"
            done < "$FIFO_BC"
            sleep 0.1
        done
    ) &
    LOGGER_BC_PID=$!

    # MCXboxBroadcast Logger with interactive Auth Prompt Banner
    (
        while [ "$RUNNING" = true ]; do
            while IFS= read -r line; do
                echo -e "\033[0;35m[XboxBroadcast]\033[0m $line"

                # Detect Microsoft device authentication challenge
                if [[ "$line" =~ microsoft\.com\/link ]] && [[ "$line" =~ [A-Z0-9]{8,} ]]; then
                    local code
                    code=$(echo "$line" | grep -o -E '[A-Z0-9]{8,}' | head -n 1)
                    echo -e "\033[1;33m"
                    echo "========================================================================"
                    echo "  [XboxBroadcast] ACTION REQUIRED: Microsoft Account Sign-In"
                    echo "  1. Open: https://www.microsoft.com/link"
                    echo "  2. Enter Code: ${code}"
                    echo "========================================================================"
                    echo -e "\033[0m"
                fi
            done < "$FIFO_XBL"
            sleep 0.1
        done
    ) &
    LOGGER_XBL_PID=$!
}

# ------------------------------------------------------------------------------
# Process Management
# ------------------------------------------------------------------------------
start_bedrockconnect() {
    if [ -n "$BC_PID" ] && kill -0 "$BC_PID" 2>/dev/null; then
        return 0
    fi

    log_info "Starting BedrockConnect (RAM: ${JAVA_MEMORY_BC}MB, Port: ${SERVER_PORT})..."
    (
        cd "$BC_DIR"
        exec java -Xms128M -Xmx"${JAVA_MEMORY_BC}"M \
            -jar "$BC_JAR" \
            nodb=true \
            port="${SERVER_PORT}" \
            bindip=0.0.0.0 \
            custom_servers=serverlist.json > "$FIFO_BC" 2>&1
    ) &
    BC_PID=$!
}

start_broadcaster() {
    if [ -n "$XBL_PID" ] && kill -0 "$XBL_PID" 2>/dev/null; then
        return 0
    fi

    log_info "Starting MCXboxBroadcast (RAM: ${JAVA_MEMORY_XBL}MB)..."
    (
        cd "$XBL_DIR"
        exec java -Xms128M -Xmx"${JAVA_MEMORY_XBL}"M \
            -jar "$XBL_JAR" > "$FIFO_XBL" 2>&1
    ) &
    XBL_PID=$!
}

stop_services() {
    log_info "Gracefully stopping services..."
    if [ -n "$BC_PID" ] && kill -0 "$BC_PID" 2>/dev/null; then
        kill -TERM "$BC_PID" 2>/dev/null || true
    fi
    if [ -n "$XBL_PID" ] && kill -0 "$XBL_PID" 2>/dev/null; then
        kill -TERM "$XBL_PID" 2>/dev/null || true
    fi

    # Wait up to 10 seconds for clean shutdown
    for _ in {1..20}; do
        local bc_active=0
        local xbl_active=0
        kill -0 "$BC_PID" 2>/dev/null && bc_active=1
        kill -0 "$XBL_PID" 2>/dev/null && xbl_active=1

        if [ "$bc_active" -eq 0 ] && [ "$xbl_active" -eq 0 ]; then
            break
        fi
        sleep 0.5
    done

    # Force kill if still lingering
    kill -9 "$BC_PID" 2>/dev/null || true
    kill -9 "$XBL_PID" 2>/dev/null || true
    BC_PID=""
    XBL_PID=""
}

# ------------------------------------------------------------------------------
# Auto-Update Routine
# ------------------------------------------------------------------------------
check_for_updates() {
    [ "$UPDATING" = true ] && return 0
    UPDATING=true

    log_info "Checking for software updates..."
    local updated_any=false

    # 1. BedrockConnect update check
    local current_bc="unknown"
    [ -f "$BC_VER_FILE" ] && current_bc=$(cat "$BC_VER_FILE" | tr -d '\r\n ')
    local latest_bc
    latest_bc=$(get_latest_release "Pugmatt/BedrockConnect")

    if [ -n "$latest_bc" ] && [ "$latest_bc" != "$current_bc" ]; then
        log_info "BedrockConnect update detected: ${current_bc} -> ${latest_bc}. Downloading..."
        local bc_tmp="${BC_DIR}/${BC_JAR}.tmp"
        if download_file "https://github.com/Pugmatt/BedrockConnect/releases/download/${latest_bc}/${BC_JAR}" "$bc_tmp"; then
            if validate_jar "$bc_tmp"; then
                mv "$bc_tmp" "${BC_DIR}/${BC_JAR}"
                echo "$latest_bc" > "$BC_VER_FILE"
                log_info "BedrockConnect successfully updated to ${latest_bc}!"
                updated_any=true
            else
                log_warn "BedrockConnect update validation failed; skipping."
                rm -f "$bc_tmp"
            fi
        fi
    fi

    # 2. MCXboxBroadcast update check
    local current_xbl="unknown"
    [ -f "$XBL_VER_FILE" ] && current_xbl=$(cat "$XBL_VER_FILE" | tr -d '\r\n ')
    local latest_xbl
    latest_xbl=$(get_latest_release "MCXboxBroadcast/Broadcaster")

    if [ -n "$latest_xbl" ] && [ "$latest_xbl" != "$current_xbl" ]; then
        log_info "MCXboxBroadcast update detected: ${current_xbl} -> ${latest_xbl}. Downloading..."
        local xbl_tmp="${XBL_DIR}/${XBL_JAR}.tmp"
        if download_file "https://github.com/MCXboxBroadcast/Broadcaster/releases/download/${latest_xbl}/${XBL_JAR}" "$xbl_tmp"; then
            if validate_jar "$xbl_tmp"; then
                mv "$xbl_tmp" "${XBL_DIR}/${XBL_JAR}"
                echo "$latest_xbl" > "$XBL_VER_FILE"
                log_info "MCXboxBroadcast successfully updated to ${latest_xbl}!"
                updated_any=true
            else
                log_warn "MCXboxBroadcast update validation failed; skipping."
                rm -f "$xbl_tmp"
            fi
        fi
    fi

    if [ "$updated_any" = true ]; then
        if [ "$AUTO_UPDATE_RESTART" = "true" ] || [ "$AUTO_UPDATE_RESTART" = "1" ]; then
            log_info "Auto-restart is enabled. Performing graceful rolling restart..."
            stop_services
            start_bedrockconnect
            start_broadcaster
            log_info "Both services successfully restarted with updated binaries!"
        else
            log_info "Updates installed! Changes will take effect on next server reboot."
        fi
    else
        log_info "All applications are up to date."
    fi

    UPDATING=false
}

# ------------------------------------------------------------------------------
# Shutdown & Teardown Handlers
# ------------------------------------------------------------------------------
cleanup() {
    RUNNING=false
    log_info "Shutdown signal received. Stopping all components..."
    trap '' SIGTERM SIGINT SIGHUP

    stop_services

    kill "$LOGGER_BC_PID" 2>/dev/null || true
    kill "$LOGGER_XBL_PID" 2>/dev/null || true
    rm -f "$FIFO_BC" "$FIFO_XBL"

    log_info "Server stopped cleanly. Goodbye!"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# ------------------------------------------------------------------------------
# Console Stdin Handler
# ------------------------------------------------------------------------------
listen_stdin() {
    while [ "$RUNNING" = true ] && IFS= read -r cmd; do
        cmd=$(echo "$cmd" | tr -d '\r\n ')
        case "$cmd" in
            stop|exit|end)
                log_info "Stop command received via console."
                cleanup
                ;;
            update|check-update)
                log_info "Manual update check triggered via console."
                check_for_updates
                ;;
            restart)
                log_info "Manual restart triggered via console."
                stop_services
                start_bedrockconnect
                start_broadcaster
                ;;
            status)
                local bc_st="STOPPED"
                local xbl_st="STOPPED"
                kill -0 "$BC_PID" 2>/dev/null && bc_st="RUNNING (PID $BC_PID)"
                kill -0 "$XBL_PID" 2>/dev/null && xbl_st="RUNNING (PID $XBL_PID)"
                echo "=========================================="
                echo " BedrockBridge Status:"
                echo " - BedrockConnect: $bc_st"
                echo " - MCXboxBroadcast: $xbl_st"
                echo " - Auto-Update Interval: ${UPDATE_CHECK_INTERVAL} minutes"
                echo "=========================================="
                ;;
            help)
                echo "Supported commands: stop, restart, update, status, help"
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Main Execution Entrypoint
# ------------------------------------------------------------------------------
log_info "Initializing BedrockConnect + MCXboxBroadcast Environment..."
init_workspace
setup_fifos

start_bedrockconnect
start_broadcaster

# Signal to Wings that the server is successfully running
sleep 2
echo "Both BedrockConnect and MCXboxBroadcast are running!"

listen_stdin &
STDIN_PID=$!

LAST_CHECK=$(date +%s)

# Supervisor & Watchdog Loop
while [ "$RUNNING" = true ]; do
    sleep 5

    # Health Check: BedrockConnect
    if [ "$UPDATING" = false ] && ! kill -0 "$BC_PID" 2>/dev/null; then
        log_warn "BedrockConnect is unexpectedly down! Relaunching..."
        start_bedrockconnect
    fi

    # Health Check: MCXboxBroadcast
    if [ "$UPDATING" = false ] && ! kill -0 "$XBL_PID" 2>/dev/null; then
        log_warn "MCXboxBroadcast is unexpectedly down! Relaunching..."
        start_broadcaster
    fi

    # Update Interval Check
    NOW=$(date +%s)
    if [ $(( NOW - LAST_CHECK )) -ge "$CHECK_INTERVAL_SEC" ]; then
        check_for_updates
        LAST_CHECK=$(date +%s)
    fi
done

cleanup
