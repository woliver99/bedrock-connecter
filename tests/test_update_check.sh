#!/usr/bin/env bash
# ==============================================================================
# Update Checker & Binary Verification Test
# ==============================================================================
set -e

echo "=== Running Live Update Checker Tests ==="

get_latest_release() {
    local repo="$1"
    local tag=""
    local location
    location=$(curl -sI -m 10 "https://github.com/${repo}/releases/latest" 2>/dev/null | grep -i "^location:" | tr -d '\r' | awk '{print $2}')
    if [ -n "$location" ]; then
        tag=$(basename "$location")
    fi
    if [ -z "$tag" ]; then
        tag=$(curl -s -m 10 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    fi
    echo "$tag"
}

validate_jar() {
    local file="$1"
    [ ! -f "$file" ] && return 1
    local size
    size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null || echo 0)
    [ "$size" -lt 500000 ] && return 1
    local magic
    magic=$(head -c 2 "$file" 2>/dev/null)
    [ "$magic" != "PK" ] && return 1
    if command -v unzip >/dev/null 2>&1; then
        unzip -tq "$file" >/dev/null 2>&1 || return 1
    fi
    return 0
}

# 1. Test release tag resolution
echo -n "Checking BedrockConnect latest release tag... "
BC_TAG=$(get_latest_release "Pugmatt/BedrockConnect")
if [ -z "$BC_TAG" ]; then
    echo "FAILED"
    exit 1
fi
echo "OK (${BC_TAG})"

echo -n "Checking MCXboxBroadcast latest release tag... "
XBL_TAG=$(get_latest_release "MCXboxBroadcast/Broadcaster")
if [ -z "$XBL_TAG" ]; then
    echo "FAILED"
    exit 1
fi
echo "OK (${XBL_TAG})"

# 2. Test Jar Validation with dummy & corrupted files
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo -n "Testing validation against empty file... "
touch "$TMP_DIR/empty.jar"
if validate_jar "$TMP_DIR/empty.jar"; then
    echo "FAILED (empty file passed validation)"
    exit 1
fi
echo "OK (correctly rejected)"

echo -n "Testing validation against small file with PK header... "
echo "PKfakeheadercontents" > "$TMP_DIR/fake.jar"
if validate_jar "$TMP_DIR/fake.jar"; then
    echo "FAILED (small fake jar passed validation)"
    exit 1
fi
echo "OK (correctly rejected)"

echo -n "Testing validation against live BedrockConnect header/head download... "
# Download first 600KB of live BedrockConnect jar to test partial rejection if incomplete
curl -sSL -r 0-600000 -o "$TMP_DIR/truncated.jar" "https://github.com/Pugmatt/BedrockConnect/releases/download/${BC_TAG}/BedrockConnect-1.0-SNAPSHOT.jar"
if command -v unzip >/dev/null 2>&1; then
    if validate_jar "$TMP_DIR/truncated.jar"; then
        echo "FAILED (truncated zip passed integrity check)"
        exit 1
    fi
    echo "OK (unzip integrity caught truncated download)"
else
    echo "SKIPPED (unzip not installed on host)"
fi

echo "=== All Update Checker Tests Passed! ==="
