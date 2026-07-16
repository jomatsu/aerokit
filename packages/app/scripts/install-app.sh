#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/app-metadata.sh"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_DIR="$INSTALL_DIR/$APP_NAME.app"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENT_DIR/$BUNDLE_ID.plist"
LOG_DIR="$HOME/Library/Logs/$APP_NAME"

mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENT_DIR" "$LOG_DIR"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-auto}" \
  OUTPUT_DIR="$INSTALL_DIR" \
  "$SCRIPT_DIR/build-app.sh" >/dev/null

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

plutil -create xml1 "$LAUNCH_AGENT"
plutil -insert Label -string "$BUNDLE_ID" "$LAUNCH_AGENT"
plutil -insert ProgramArguments -array "$LAUNCH_AGENT"
plutil -insert ProgramArguments.0 -string /usr/bin/open "$LAUNCH_AGENT"
plutil -insert ProgramArguments.1 -string -g "$LAUNCH_AGENT"
plutil -insert ProgramArguments.2 -string "$APP_DIR" "$LAUNCH_AGENT"
plutil -insert RunAtLoad -bool true "$LAUNCH_AGENT"
plutil -insert StandardOutPath -string "$LOG_DIR/stdout.log" "$LAUNCH_AGENT"
plutil -insert StandardErrorPath -string "$LOG_DIR/stderr.log" "$LAUNCH_AGENT"
plutil -lint "$LAUNCH_AGENT" >/dev/null

launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
launchctl kickstart -k "gui/$(id -u)/$BUNDLE_ID"

echo "$APP_DIR"
