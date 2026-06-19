#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIGURATION="release"
OUTPUT_DIR="$PROJECT_ROOT/dist"
SKIP_SIGN="0"
BUILD_NUMBER="${ORACLE_BUILD_NUMBER:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --skip-sign)
            SKIP_SIGN="1"
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

VERSION=$(grep -o 'version = "[^"]*"' "$PROJECT_ROOT/Sources/OracleOS/Common/Types.swift" | head -1 | cut -d'"' -f2)
if [[ -z "$VERSION" ]]; then
    echo "Could not determine Oracle OS version." >&2
    exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$VERSION"
fi

BUILD_APP_ARGS=(
    --configuration "$CONFIGURATION"
    --output-dir "$OUTPUT_DIR"
    --build-number "$BUILD_NUMBER"
)

if [[ "$SKIP_SIGN" == "1" ]]; then
    BUILD_APP_ARGS+=(--skip-sign)
fi

"$PROJECT_ROOT/scripts/build-controller-app.sh" "${BUILD_APP_ARGS[@]}"

APP_BUNDLE="$OUTPUT_DIR/Oracle Controller.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "App bundle not found at $APP_BUNDLE" >&2
    exit 1
fi

DMG_STAGE="$PROJECT_ROOT/.build/controller-dmg-stage"
RW_DMG="$OUTPUT_DIR/Oracle-Controller-$VERSION-rw.dmg"
FINAL_DMG="$OUTPUT_DIR/Oracle-Controller-$VERSION.dmg"
BACKGROUND_DIR="$DMG_STAGE/.background"
BACKGROUND_PNG="$BACKGROUND_DIR/background.png"
VOLUME_NAME="Oracle Controller"

rm -rf "$DMG_STAGE" "$RW_DMG" "$FINAL_DMG"
mkdir -p "$DMG_STAGE" "$BACKGROUND_DIR"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

if qlmanage -t -s 900 -o "$BACKGROUND_DIR" "$PROJECT_ROOT/logo.svg" >/dev/null 2>&1; then
    mv "$BACKGROUND_DIR/logo.svg.png" "$BACKGROUND_PNG"
else
    sips -s format png "$PROJECT_ROOT/logo.svg" --out "$BACKGROUND_PNG" >/dev/null
fi

hdiutil create -srcfolder "$DMG_STAGE" -volname "$VOLUME_NAME" -fs HFS+ -format UDRW "$RW_DMG" >/dev/null

if [[ "${ORACLE_DMG_CUSTOMIZE:-0}" == "1" ]] && command -v osascript >/dev/null 2>&1; then
    MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")
    DEVICE_NAME=$(echo "$MOUNT_OUTPUT" | awk 'NR==1 { print $1 }')
    MOUNT_PATH=$(echo "$MOUNT_OUTPUT" | awk '/\/Volumes\// { print $3; exit }')

    if [[ -n "$MOUNT_PATH" && -d "$MOUNT_PATH" ]]; then
        mkdir -p "$MOUNT_PATH/.background"
        cp "$BACKGROUND_PNG" "$MOUNT_PATH/.background/background.png"

        osascript <<EOF >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {120, 120, 880, 560}
        set arrangement of icon view options of container window to not arranged
        set icon size of icon view options of container window to 96
        try
            set background picture of icon view options of container window to file ".background:background.png"
        end try
        set position of item "Oracle Controller.app" of container window to {200, 260}
        set position of item "Applications" of container window to {540, 260}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
EOF
        hdiutil detach "${DEVICE_NAME:-$MOUNT_PATH}" -force >/dev/null || true
        sleep 2
    fi
fi

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null
rm -f "$RW_DMG"

if [[ "$SKIP_SIGN" != "1" && -n "${APPLE_DEVELOPER_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$APPLE_DEVELOPER_IDENTITY" "$FINAL_DMG"
fi

echo "Built DMG:"
echo "  $FINAL_DMG"
shasum -a 256 "$FINAL_DMG"
