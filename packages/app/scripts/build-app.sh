#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/app-metadata.sh"

# Default to the single version source the binary itself compiles in, so a
# local build can never disagree with `AeroKit --version`; CI overrides it
# from the release tag (and separately checks the two match).
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' \
    "$ROOT_DIR/Sources/AeroKitCore/AppVersion.swift")"
fi
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCHS="${ARCHS:-$(uname -m)}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "VERSION must be a semantic version without a leading v: $VERSION" >&2
  exit 1
fi

if [[ ! -f "$ICON_FILE" ]]; then
  echo "App icon is missing: $ICON_FILE" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "BUILD_NUMBER must be an integer: $BUILD_NUMBER" >&2
  exit 1
fi

read -r -a BUILD_ARCHS <<< "$ARCHS"
if [[ "${#BUILD_ARCHS[@]}" -eq 0 ]]; then
  echo "ARCHS must contain at least one architecture" >&2
  exit 1
fi

BUILD_ARGS=(-c release --product "$APP_NAME")
for arch in "${BUILD_ARCHS[@]}"; do
  case "$arch" in
    arm64|x86_64) BUILD_ARGS+=(--arch "$arch") ;;
    *)
      echo "Unsupported architecture: $arch" >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BINARY" ]]; then
  echo "Built executable not found: $BINARY" >&2
  exit 1
fi

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 755 "$BINARY" "$MACOS_DIR/$APP_NAME"
cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MINIMUM_MACOS_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null

if [[ "$CODESIGN_IDENTITY" == "auto" ]]; then
  CODESIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
      sed -n 's/.*"\(Apple Development:.*\)".*/\1/p' |
      sed -n '1p'
  )"
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
fi

SIGN_ARGS=(--force --sign "$CODESIGN_IDENTITY")
if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

printf '%s\n' "$APP_DIR"
