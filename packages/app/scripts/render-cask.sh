#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/app-metadata.sh"

VERSION="${1:?Usage: render-cask.sh VERSION SHA256 OUTPUT}"
SHA256="${2:?Usage: render-cask.sh VERSION SHA256 OUTPUT}"
OUTPUT="${3:?Usage: render-cask.sh VERSION SHA256 OUTPUT}"
RELEASE_REPOSITORY="${RELEASE_REPOSITORY:-jomatsu/aerokit}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Cask versions must be stable semantic versions: $VERSION" >&2
  exit 1
fi

if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Invalid SHA-256: $SHA256" >&2
  exit 1
fi

if [[ ! "$RELEASE_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "Invalid RELEASE_REPOSITORY: $RELEASE_REPOSITORY" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<CASK
cask "aerokit" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$RELEASE_REPOSITORY/releases/download/v#{version}/$APP_NAME-#{version}.zip"
  name "$APP_NAME"
  desc "AeroSpace companion with workspace switching, Exposé, and trackpad navigation"
  homepage "https://github.com/$RELEASE_REPOSITORY"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :$MINIMUM_MACOS_CASK

  app "$APP_NAME.app"
  binary "#{appdir}/$APP_NAME.app/Contents/MacOS/$APP_NAME", target: "aerokit"

  uninstall launchctl: "$BUNDLE_ID",
            quit:      "$BUNDLE_ID"

  zap trash: [
    "~/Library/Application Support/$APP_NAME",
    "~/Library/Caches/$BUNDLE_ID",
    "~/Library/LaunchAgents/$BUNDLE_ID.plist",
    "~/Library/Logs/$APP_NAME",
    "~/Library/Preferences/$BUNDLE_ID.plist",
    "~/Library/Saved Application State/$BUNDLE_ID.savedState",
  ]
end
CASK

printf '%s\n' "$OUTPUT"
