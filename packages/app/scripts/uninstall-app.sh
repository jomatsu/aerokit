#!/bin/bash

set -euo pipefail

APP_NAME="AeroKit"
BUNDLE_ID="com.nasubikun.aerokit"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_DIR="$INSTALL_DIR/$APP_NAME.app"

PURGE="false"
if [[ "${1:-}" == "--purge" ]]; then
  PURGE="true"
fi

# Retire any legacy LaunchAgent from installs that predate SMAppService. The
# current login item is registered by the app and disappears with the bundle.
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true

rm -rf "$APP_DIR"
rm -rf "$HOME/Library/Logs/$APP_NAME"

echo "Removed $APP_DIR and its logs."

if [[ "$PURGE" == "true" ]]; then
  rm -rf "$HOME/Library/Application Support/AeroKit"
  rm -rf "$HOME/Pictures/AeroSpace Workspaces"
  rm -rf "$HOME/Library/Caches/AeroSpaceWorkspaceSnapshots"
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  echo "Purged snapshots and preferences."
else
  echo "Kept snapshots and preferences. Re-run with --purge to remove them too."
fi
