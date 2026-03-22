#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <path-to-app-or-dmg>" >&2
    exit 1
fi

TARGET_PATH="$1"
if [[ ! -e "$TARGET_PATH" ]]; then
    echo "Missing target: $TARGET_PATH" >&2
    exit 1
fi

if [[ -n "${APPLE_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$TARGET_PATH" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
elif [[ -n "${APPLE_NOTARY_KEY_PATH:-}" && -n "${APPLE_NOTARY_KEY_ID:-}" && -n "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
    xcrun notarytool submit \
        "$TARGET_PATH" \
        --key "$APPLE_NOTARY_KEY_PATH" \
        --key-id "$APPLE_NOTARY_KEY_ID" \
        --issuer "$APPLE_NOTARY_ISSUER_ID" \
        --wait
else
    echo "Missing notarytool credentials. Set APPLE_NOTARY_PROFILE or APPLE_NOTARY_KEY_PATH/APPLE_NOTARY_KEY_ID/APPLE_NOTARY_ISSUER_ID." >&2
    exit 1
fi

xcrun stapler staple "$TARGET_PATH"
xcrun stapler validate "$TARGET_PATH"
spctl --assess --type open --context context:primary-signature "$TARGET_PATH"

echo "Notarized and stapled:"
echo "  $TARGET_PATH"
