#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DEFAULT_DIR="$(pwd)"
TARGET_DIR="${1:-$DEFAULT_DIR}/apps"

if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR) No '$TARGET_DIR' dir"
    exit -1
fi

echo "Script Dir : $SCRIPT_DIR"
echo "Target Dir : $TARGET_DIR"

"$SCRIPT_DIR/script_files/read_ipk.sh" "$TARGET_DIR"

