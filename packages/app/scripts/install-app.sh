#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/app-metadata.sh"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_DIR="$INSTALL_DIR/$APP_NAME.app"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"

# Assemble the bundle in a staging directory next to its destination (same
# volume, so the final move is atomic) and swap it in only once complete: a
# failure mid-assembly must neither leave a half-written AeroKit.app nor
# have deleted the working install it was replacing.
mkdir -p "$INSTALL_DIR"
STAGING_DIR="$(mktemp -d "$INSTALL_DIR/.$APP_NAME.staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-auto}" \
  OUTPUT_DIR="$STAGING_DIR" \
  "$SCRIPT_DIR/build-app.sh" >/dev/null
STAGED_APP="$STAGING_DIR/$APP_NAME.app"

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
