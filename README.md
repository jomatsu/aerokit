# aerokit

A monorepo of [AeroSpace](https://github.com/nikitabobko/AeroSpace) companion tools for macOS.

**AeroKit** is a menu-bar app that adds the pieces AeroSpace deliberately leaves out:
a Cmd-Tab-style **workspace switcher** with snapshot previews, and an Exposé-style
**window overview** of the focused workspace or app.

<!-- TODO: add screenshots, e.g.
![Workspace switcher](docs/images/switcher.png)
![Exposé overview](docs/images/expose.png)
-->

## Requirements

- macOS 14 (Sonoma) or later
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) installed and running
  (`brew install --cask nikitabobko/tap/aerospace`)
- **Screen Recording** permission for window previews (the app works without it,
  minus previews)

## Install

Build and install from source:

```sh
git clone https://github.com/jomatsu/aerokit.git
cd aerokit/packages/app
scripts/install-app.sh
```

This builds a release binary, wraps it into `~/Applications/AeroKit.app`, and
registers a LaunchAgent so it starts at login.

<!-- TODO: enable after the first signed release:
```sh
brew install --cask jomatsu/tap/aerokit
```
-->

See [`packages/app`](packages/app) for features, default hotkeys, and CLI flags.

## Packages

| Package | Description |
| --- | --- |
| [`packages/app`](packages/app) | AeroKit — menu-bar app bundling the workspace switcher (snapshot previews) and the Exposé-style window overview |

## Development

```sh
make bootstrap  # install SwiftFormat, SwiftLint and AeroSpace through Homebrew
make format     # format all packages
make lint       # lint all packages
make build      # build all packages
make test       # test all packages
make check      # lint + build + test
```

Formatting and linting rules are shared across packages via the root `.swiftformat` and `.swiftlint.yml`.

Release maintainers should follow [`docs/releasing.md`](docs/releasing.md) for
Developer ID signing, notarization, GitHub Releases, and Homebrew tap updates.

## License

[MIT](LICENSE)
