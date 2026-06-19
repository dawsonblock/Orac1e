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

APP_NAME="Oracle Controller"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_PRODUCTS_DIR="$PROJECT_ROOT/.build/$CONFIGURATION"

mkdir -p "$OUTPUT_DIR"

echo "Building Oracle Controller app bundle ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product OracleController --product OracleControllerHost

CONTROLLER_BINARY="$BUILD_PRODUCTS_DIR/OracleController"
HOST_BINARY="$BUILD_PRODUCTS_DIR/OracleControllerHost"

if [[ ! -x "$CONTROLLER_BINARY" ]]; then
    echo "Missing controller binary at $CONTROLLER_BINARY" >&2
    exit 1
fi

if [[ ! -x "$HOST_BINARY" ]]; then
    echo "Missing host binary at $HOST_BINARY" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$RESOURCES_DIR"

cp "$CONTROLLER_BINARY" "$MACOS_DIR/OracleController"
cp "$HOST_BINARY" "$HELPERS_DIR/OracleControllerHost"
chmod +x "$MACOS_DIR/OracleController" "$HELPERS_DIR/OracleControllerHost"

PLIST_TEMPLATE="$PROJECT_ROOT/AppResources/OracleController/Info.plist"
PLIST_DEST="$CONTENTS_DIR/Info.plist"
sed \
    -e "s/__ORACLE_VERSION__/$VERSION/g" \
    -e "s/__ORACLE_BUILD__/$BUILD_NUMBER/g" \
    "$PLIST_TEMPLATE" > "$PLIST_DEST"

cp "$PROJECT_ROOT/AppResources/OracleController/Help.md" "$RESOURCES_DIR/Help.md"
cp "$PROJECT_ROOT/AppResources/OracleController/ReleaseNotes.md" "$RESOURCES_DIR/ReleaseNotes.md"

mkdir -p "$RESOURCES_DIR/SampleRecipes"
cp "$PROJECT_ROOT/recipes/"*.json "$RESOURCES_DIR/SampleRecipes/" 2>/dev/null || true

mkdir -p "$RESOURCES_DIR/VisionBootstrap/vision-sidecar"
rsync -a \
    --delete \
    --exclude ".venv" \
    --exclude ".mypy_cache" \
    --exclude "__pycache__" \
    --exclude "tests" \
    --exclude "docs" \
    --exclude "*.md" \
    --exclude "mypy.ini" \
    "$PROJECT_ROOT/vision-sidecar/" \
    "$RESOURCES_DIR/VisionBootstrap/vision-sidecar/"

generate_icon() {
    local temp_dir="$PROJECT_ROOT/.build/controller-icon"
    local base_png="$temp_dir/base.png"
    local iconset_dir="$temp_dir/AppIcon.iconset"

    rm -rf "$temp_dir"
    mkdir -p "$temp_dir" "$iconset_dir"

    if qlmanage -t -s 1024 -o "$temp_dir" "$PROJECT_ROOT/logo.svg" >/dev/null 2>&1; then
        mv "$temp_dir/logo.svg.png" "$base_png"
    else
        sips -s format png "$PROJECT_ROOT/logo.svg" --out "$base_png" >/dev/null
    fi

    for size in 16 32 128 256 512; do
        local double=$(( size * 2 ))
        sips -z "$size" "$size" "$base_png" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
        sips -z "$double" "$double" "$base_png" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
    done

    iconutil -c icns "$iconset_dir" -o "$RESOURCES_DIR/AppIcon.icns"
}

generate_icon

sign_app() {
    local app_path="$1"
    local identity="${APPLE_DEVELOPER_IDENTITY:-}"
    local app_entitlements="$PROJECT_ROOT/AppResources/OracleController/OracleController.entitlements"
    local host_entitlements="$PROJECT_ROOT/AppResources/OracleController/OracleControllerHost.entitlements"

    if [[ "$SKIP_SIGN" == "1" ]]; then
        codesign --force --deep --sign - "$app_path"
        return
    fi

    if [[ -n "$identity" ]]; then
        codesign --force --timestamp --options runtime --entitlements "$host_entitlements" --sign "$identity" "$HELPERS_DIR/OracleControllerHost"
        codesign --force --timestamp --options runtime --entitlements "$app_entitlements" --sign "$identity" "$MACOS_DIR/OracleController"
        codesign --force --timestamp --options runtime --entitlements "$app_entitlements" --sign "$identity" "$app_path"
    else
        codesign --force --deep --sign - "$app_path"
    fi
}

sign_app "$APP_BUNDLE"

echo "Built app bundle:"
echo "  $APP_BUNDLE"
