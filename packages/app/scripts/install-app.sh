#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/app-metadata.sh"
# Dev installs use their own bundle identifier and app name so Screen
# Recording / Accessibility grants, the login item, LaunchServices, and
# the System Settings entries stay separate and recognizable next to the
# Homebrew/release app at /Applications.
export AEROKIT_BUNDLE_ID="${AEROKIT_BUNDLE_ID:-$DEV_BUNDLE_ID}"
export AEROKIT_APP_NAME="${AEROKIT_APP_NAME:-$DEV_APP_NAME}"
# Apply the overrides in this shell too: APP_NAME/APP_DIR drive where the
# build lands and which processes get taken over.
APP_NAME="$AEROKIT_APP_NAME"
BUNDLE_ID="$AEROKIT_BUNDLE_ID"
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
# Take over from every sibling install: the release app ("AeroKit") and
# any pre-rename dev copy.
for RUNNING_NAME in "$APP_NAME" AeroKit; do
  /usr/bin/pkill -x "$RUNNING_NAME" >/dev/null 2>&1 || true
done
if [[ "$APP_NAME" != "AeroKit" ]]; then
  rm -rf "$INSTALL_DIR/AeroKit.app"
fi
rm -rf "$APP_DIR"
mv "$STAGED_APP" "$APP_DIR"
/usr/bin/open -g "$APP_DIR"

echo "$APP_DIR"
