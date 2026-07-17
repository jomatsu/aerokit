# Releasing AeroKit

A release tag builds a Universal macOS app, signs it with Developer ID,
notarizes it, publishes a GitHub Release, and updates
`jomatsu/homebrew-tap`.

## One-time setup

The release repository and every release asset referenced by the cask must be
publicly downloadable. The current workflow publishes to `jomatsu/aerokit`, so
that repository must be public before the first release tag is pushed.

Create the tap repository with Homebrew's generated CI files:

```sh
brew tap-new jomatsu/tap
gh repo create jomatsu/homebrew-tap \
  --public \
  --source "$(brew --repository jomatsu/tap)" \
  --push
```

Configure these Actions secrets in `jomatsu/aerokit`:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE` | Base64-encoded `.p12` containing a Developer ID Application certificate and private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID |
| `APPLE_API_PRIVATE_KEY` | Complete contents of the matching `AuthKey_*.p8` file |
| `HOMEBREW_TAP_DEPLOY_KEY` | Private half of a write-enabled deploy key scoped to `jomatsu/homebrew-tap` |

On macOS, encode an exported certificate and set the secrets with `gh`:

```sh
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_CERTIFICATE -R jomatsu/aerokit
gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD -R jomatsu/aerokit
gh secret set APPLE_API_KEY_ID -R jomatsu/aerokit
gh secret set APPLE_API_ISSUER_ID -R jomatsu/aerokit
gh secret set APPLE_API_PRIVATE_KEY -R jomatsu/aerokit < AuthKey_KEYID.p8
```

Use a dedicated write-enabled deploy key for the tap, and store its private
half as `HOMEBREW_TAP_DEPLOY_KEY`. Do not reuse a personal SSH key or a broad
GitHub access token.

## Publish a version

Run the full local check, then push a semantic-version tag:

```sh
make check
git tag v0.1.0
git push origin v0.1.0
```

The release workflow rejects tags that do not look like `v1.2.3`. It will not
publish an unsigned or unnotarized build.

After the workflow completes, verify installation from a clean machine:

```sh
brew install --cask jomatsu/tap/aerokit
brew uninstall --cask aerokit
```

## Local app bundle

`build-app.sh` defaults to an ad-hoc signature for local builds. Release builds
must provide a Developer ID identity explicitly.

```sh
ARCHS="arm64 x86_64" \
OUTPUT_DIR="$PWD/dist" \
CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
  packages/app/scripts/build-app.sh
```

`VERSION` defaults to `AppVersion.current`; the release workflow overrides
it from the tag and fails when the two disagree, so bump
`Sources/AeroKitCore/AppVersion.swift` before tagging.
