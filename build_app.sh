#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$REPO_ROOT/VideoMinifier.xcodeproj"
SCHEME="VideoMinifier"
CONFIGURATION="Release"
DERIVED_DATA="$REPO_ROOT/build/derived_data"
OUTPUT_APP="$REPO_ROOT/VideoMinifier.app"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode Command Line Tools." >&2
  exit 1
fi

if [[ ! -d "$PROJECT" ]]; then
  echo "Xcode project not found at: $PROJECT" >&2
  exit 1
fi

echo "Cleaning derived data and previous app..."
rm -rf "$DERIVED_DATA" "$OUTPUT_APP"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  clean build

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/VideoMinifier.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Built app not found at: $BUILT_APP" >&2
  exit 2
fi

echo "Copying localizations into app bundle..."
mkdir -p "$BUILT_APP/Contents/Resources"
for lproj_dir in "$REPO_ROOT/VideoMinifier/Resources"/*.lproj; do
  [[ -d "$lproj_dir" ]] || continue
  lang_dir="$BUILT_APP/Contents/Resources/$(basename "$lproj_dir")"
  mkdir -p "$lang_dir"
  if [[ -f "$lproj_dir/Localizable.strings" ]]; then
    cp -f "$lproj_dir/Localizable.strings" "$lang_dir/"
  fi
done

echo "Copying app to repo root..."
cp -R "$BUILT_APP" "$OUTPUT_APP"

echo "Done: $OUTPUT_APP"
