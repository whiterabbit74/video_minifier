#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./bin/release_notarize.sh \
#       "/path/to/Видео-Сжимака.app" \
#       "Developer ID Application: YOUR NAME (TEAMID)" \
#       TEAMID \
#       APPLE_ID_EMAIL \
#       APP_SPECIFIC_PASSWORD
#
# Notes:
# - Run on macOS with Xcode CLT installed.
# - The script will sign any embedded ffmpeg at Resources/ffmpeg and Resources/bin/ffmpeg if present.
# - Hardened Runtime is enabled. Entitlements are taken from VideoSzhimaka/VideoSzhimaka.entitlements if available next to this script.

APP_PATH=${1:-}
DEV_ID=${2:-}
TEAM_ID=${3:-}
APPLE_ID=${4:-}
APP_PWD=${5:-}

if [[ -z "$APP_PATH" || -z "$DEV_ID" || -z "$TEAM_ID" || -z "$APPLE_ID" || -z "$APP_PWD" ]]; then
  echo "Usage: $0 <APP_PATH> <DEVELOPER_ID> <TEAM_ID> <APPLE_ID> <APP_SPECIFIC_PASSWORD>" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at: $APP_PATH" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTITLEMENTS_PATH="$REPO_ROOT/VideoSzhimaka/VideoSzhimaka.entitlements"

if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
  echo "Entitlements not found at $ENTITLEMENTS_PATH. Proceeding without entitlements." >&2
fi

function maybe_sign() {
  local target="$1"
  if [[ -e "$target" ]]; then
    echo "Signing: $target"
    if [[ -f "$ENTITLEMENTS_PATH" ]]; then
      codesign -s "$DEV_ID" --force --options runtime --entitlements "$ENTITLEMENTS_PATH" "$target"
    else
      codesign -s "$DEV_ID" --force --options runtime "$target"
    fi
  fi
}

# Sign embedded ffmpeg first (if present)
maybe_sign "$APP_PATH/Contents/Resources/ffmpeg"
maybe_sign "$APP_PATH/Contents/Resources/bin/ffmpeg"

# Sign the entire app bundle (deep)
echo "Signing app bundle: $APP_PATH"
if [[ -f "$ENTITLEMENTS_PATH" ]]; then
  codesign -s "$DEV_ID" --force --options runtime --entitlements "$ENTITLEMENTS_PATH" --deep "$APP_PATH"
else
  codesign -s "$DEV_ID" --force --options runtime --deep "$APP_PATH"
fi

# Verify codesign
echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH" || true

# Zip for notarization
ZIP_PATH="${APP_PATH%*.app}.zip"
echo "Creating zip: $ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Notarize (synchronous)
echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PWD" --wait

echo "Stapling ticket..."
xcrun stapler staple "$APP_PATH"

echo "Done. Notarized app at: $APP_PATH"