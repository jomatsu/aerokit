#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AeroKit"
BUNDLE_ID="com.nasubikun.aerokit"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_DIR="$INSTALL_DIR/$APP_NAME.app"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"

if [[ ! -f "$ICON_FILE" ]]; then
  echo "error: $ICON_FILE is missing" >&2
  exit 1
fi

# Keep the bundle's version in lockstep with the single source in AppVersion.swift.
VERSION="$(sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' "$ROOT_DIR/Sources/AeroKitCore/AppVersion.swift")"
VERSION="${VERSION:-0.0.0}"

cd "$ROOT_DIR"

swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"

# Assemble the bundle in a staging directory next to its destination (same
# volume, so the final move is atomic) and swap it in only once complete: a
# failure mid-assembly must neither leave a half-written AeroKit.app nor
# have deleted the working install it was replacing.
mkdir -p "$INSTALL_DIR"
STAGING_DIR="$(mktemp -d "$INSTALL_DIR/.$APP_NAME.staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$STAGED_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY" "$MACOS_DIR/$APP_NAME"
cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
  if [[ -z "$CODESIGN_IDENTITY" ]] && command -v security >/dev/null 2>&1; then
    CODESIGN_IDENTITY="$(
      security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/.*"\(Apple Development:.*\)".*/\1/p' |
        head -n 1
    )"
  fi
  if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$STAGED_APP" >/dev/null
  else
    codesign --force --deep --sign - "$STAGED_APP" >/dev/null
  fi
fi

# Retire the pre-unification apps: their LaunchAgents, processes and bundles
# are superseded by AeroKit.
for OLD_ID in com.nasubikun.aeroswitcher com.nasubikun.aeroexpose; do
  launchctl bootout "gui/$(id -u)/$OLD_ID" >/dev/null 2>&1 || true
  rm -f "$LAUNCH_AGENT_DIR/$OLD_ID.plist"
done
for OLD_APP in AeroSwitcher AeroExpose; do
  /usr/bin/pkill -x "$OLD_APP" >/dev/null 2>&1 || true
  rm -rf "$INSTALL_DIR/$OLD_APP.app"
done

# The app manages launch-at-login itself via SMAppService and migrates any
# pre-existing com.nasubikun.aerokit LaunchAgent on first launch, so the
# installer no longer writes one — it just (re)launches the fresh copy.
/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$APP_DIR"
mv "$STAGED_APP" "$APP_DIR"
/usr/bin/open -g "$APP_DIR"

echo "$APP_DIR"
