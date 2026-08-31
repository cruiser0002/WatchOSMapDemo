#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_NUM_FILE="$ROOT_DIR/build_number.txt"
OUTPUT_SWIFT="$ROOT_DIR/RadarMap/Models/AppBuildVersion.swift"

if [ ! -f "$BUILD_NUM_FILE" ]; then
    echo "1" > "$BUILD_NUM_FILE"
fi

CURRENT_NUM=$(cat "$BUILD_NUM_FILE" | tr -d '[:space:]')
if [ -z "$CURRENT_NUM" ]; then
    CURRENT_NUM=1
fi

NEXT_NUM=$((CURRENT_NUM + 1))
echo "$NEXT_NUM" > "$BUILD_NUM_FILE"

cat << SWIFT_EOF > "$OUTPUT_SWIFT"
// Generated automatically during build — do not edit manually.
import Foundation

public enum AppBuildVersion {
    public static let marketingVersion: String = "1.0.0"
    public static let buildNumber: Int = $NEXT_NUM
    public static var formatted: String {
        "v\(marketingVersion)b\(buildNumber)"
    }
}
SWIFT_EOF

echo "Incremented build number to $NEXT_NUM and updated $OUTPUT_SWIFT"
