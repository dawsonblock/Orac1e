#!/bin/bash
# build-release.sh — Build Oracle OS v2 release tarball
#
# Produces: oracle-os-{VERSION}-macos-arm64.tar.gz
# Contents:
#   oracle                                   — MCP server binary (Swift, arm64)
#   oracle-vision                             — Vision sidecar launcher (shell script)
#   ORACLE-MCP.md                             — Agent instructions
#   recipes/*.json                           — Bundled recipes
#   vision-sidecar/server.py                 — Vision sidecar Python server
#   vision-sidecar/requirements.txt          — Python dependencies
#
# Usage:
#   ./scripts/build-release.sh               # Build release tarball
#   ./scripts/build-release.sh --debug       # Build debug tarball (faster)
#
# The Homebrew formula downloads this tarball and installs:
#   /opt/homebrew/bin/oracle
#   /opt/homebrew/bin/oracle-vision
#   /opt/homebrew/share/oracle-os/ORACLE-MCP.md
#   /opt/homebrew/share/oracle-os/recipes/*.json
#   /opt/homebrew/share/oracle-os/vision-sidecar/server.py
#   /opt/homebrew/share/oracle-os/vision-sidecar/requirements.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Read version from Types.swift
VERSION=$(grep -o 'version = "[^"]*"' "$PROJECT_ROOT/Sources/OracleOS/Common/Types.swift" | head -1 | cut -d'"' -f2)
if [[ -z "$VERSION" ]]; then
    echo "ERROR: Could not read version from Types.swift" >&2
    exit 1
fi

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
fi

# Verify version consistency across all files
PYTHON_VERSION=$(grep '__version__' "$PROJECT_ROOT/vision-sidecar/server.py" | head -1 | cut -d'"' -f2)
BASH_VERSION=$(grep '^VERSION=' "$PROJECT_ROOT/vision-sidecar/oracle-vision" | cut -d'"' -f2)
if [[ "$VERSION" != "$PYTHON_VERSION" || "$VERSION" != "$BASH_VERSION" ]]; then
    echo "ERROR: Version mismatch!" >&2
    echo "  Types.swift:  $VERSION" >&2
    echo "  server.py:    $PYTHON_VERSION" >&2
    echo "  oracle-vision: $BASH_VERSION" >&2
    exit 1
fi

TARBALL_NAME="oracle-os-${VERSION}-macos-arm64.tar.gz"
STAGE_DIR="$PROJECT_ROOT/.build/${CONFIG}-stage"

echo "Building Oracle OS v${VERSION} ($CONFIG)"
echo "========================================"

# Step 1: Build Swift binary
echo ""
echo "Step 1: Building Swift binary..."
cd "$PROJECT_ROOT"

# Optimization flags for release
SWIFT_FLAGS=""
if [[ "$CONFIG" == "release" ]]; then
    echo "  Enabling Link-Time Optimization (LTO) and stripping..."
    # Apply LTO and stripping via compiler/linker flags
    # -Xswiftc -O: Optimize for speed
    # -Xswiftc -lto=llvm-full: Enable Full LTO
    # -Xlinker -dead_strip: Remove unreachable code
    SWIFT_FLAGS="-Xswiftc -O -Xswiftc -lto=llvm-full -Xlinker -dead_strip"
fi

swift build -c "$CONFIG" $SWIFT_FLAGS 2>&1

BINARY="$PROJECT_ROOT/.build/$CONFIG/oracle"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Binary not found at $BINARY" >&2
    exit 1
fi

# Final stripping for release
if [[ "$CONFIG" == "release" ]]; then
    echo "  Stripping debug symbols from $BINARY..."
    strip "$BINARY"
fi

# Verify it runs
"$BINARY" version
echo "  Binary: $BINARY ($(du -h "$BINARY" | awk '{print $1}'))"

# Step 2: Stage release files
echo ""
echo "Step 2: Staging release files..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/recipes"
mkdir -p "$STAGE_DIR/vision-sidecar"

# Binary
cp "$BINARY" "$STAGE_DIR/oracle"

# oracle-vision launcher
cp "$PROJECT_ROOT/vision-sidecar/oracle-vision" "$STAGE_DIR/oracle-vision"
chmod +x "$STAGE_DIR/oracle-vision"

# Agent instructions
cp "$PROJECT_ROOT/ORACLE-MCP.md" "$STAGE_DIR/"

# Recipes
cp "$PROJECT_ROOT/recipes/"*.json "$STAGE_DIR/recipes/" 2>/dev/null || true

# Vision sidecar - Copy full directory structure to support detectors/fusion/schema
cp -R "$PROJECT_ROOT/vision-sidecar/"* "$STAGE_DIR/vision-sidecar/"
# Cleanup non-production files from stage
rm -f "$STAGE_DIR/vision-sidecar/mypy.ini"
rm -f "$STAGE_DIR/vision-sidecar/oracle-vision" # Already at root of stage

echo "  Staged files:"
ls -la "$STAGE_DIR/"
echo ""
echo "  Staged recipes:"
ls "$STAGE_DIR/recipes/" 2>/dev/null || echo "    (none)"
echo ""
echo "  Staged vision-sidecar:"
ls "$STAGE_DIR/vision-sidecar/"

# Step 3: Create tarball
echo ""
echo "Step 3: Creating tarball..."
cd "$STAGE_DIR"
tar czf "$PROJECT_ROOT/$TARBALL_NAME" ./*
echo "  Tarball: $PROJECT_ROOT/$TARBALL_NAME"
echo "  Size: $(du -h "$PROJECT_ROOT/$TARBALL_NAME" | awk '{print $1}')"

# Step 4: Compute SHA256
echo ""
echo "Step 4: SHA256..."
SHA256=$(shasum -a 256 "$PROJECT_ROOT/$TARBALL_NAME" | awk '{print $1}')
echo "  sha256 \"$SHA256\""

# Step 5: Summary
echo ""
echo "========================================"
echo "Release: Oracle OS v${VERSION}"
echo "Tarball: $TARBALL_NAME"
echo "SHA256:  $SHA256"
echo ""
echo "To install locally:"
echo "  tar xzf $TARBALL_NAME -C /tmp/oracle-os-install"
echo "  cp /tmp/oracle-os-install/oracle /opt/homebrew/bin/"
echo "  cp /tmp/oracle-os-install/oracle-vision /opt/homebrew/bin/"
echo ""
echo "To update Homebrew formula:"
echo "  url \"https://github.com/dawsonblock/Oracle-OS/releases/download/v${VERSION}/${TARBALL_NAME}\""
echo "  sha256 \"${SHA256}\""
echo ""
echo "To create GitHub release:"
echo "  gh release create v${VERSION} $TARBALL_NAME --title \"Oracle OS v${VERSION}\""
echo "========================================"

# Cleanup
rm -rf "$STAGE_DIR"
