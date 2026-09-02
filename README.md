# AeroKit

[![CI](https://github.com/jomatsu/aerokit/actions/workflows/ci.yml/badge.svg)](https://github.com/jomatsu/aerokit/actions/workflows/ci.yml)

A visual companion layer for [AeroSpace](https://github.com/nikitabobko/AeroSpace).

AeroKit adds a Cmd-Tab-style workspace switcher, spatial Exposé and App Exposé,
and three-finger workspace navigation without changing the AeroSpace layout.

![AeroKit overview](docs/images/aerokit-overview.png)

[▶ Watch the 29-second demo](docs/demo/aerokit-demo.mp4)

- Workspace Switcher with snapshot previews
- Exposé and App Exposé with spatial window layout
- Three-finger workspace switching

## Features

### Workspace Switcher

![Workspace Switcher](docs/images/aerokit-switcher.gif)

Switch AeroSpace workspaces like apps in Cmd-Tab, with snapshots and app icons
that make the destination recognizable before switching.

### Exposé and App Exposé

![Exposé](docs/images/aerokit-expose.gif)

See the focused workspace as a spatial overview, or find every window of the
focused app across workspaces, then jump directly to the one you need.

### Trackpad Swipe

![Trackpad Swipe](docs/images/aerokit-swipe.gif)

Move between workspaces with a natural three-finger swipe and a compact HUD
that follows the gesture.

The strip can also flash for workspace switches you make outside AeroKit —
your own AeroSpace keybindings, the CLI, other automation. AeroKit never
edits your AeroSpace config: Settings › Swipe › Keyboard Switches shows the
exact line for your install (already merged into an existing hook when one
runs) — copy it into `~/.aerospace.toml` yourself and reload:

```toml
exec-on-workspace-change = ['/Applications/AeroKit.app/Contents/MacOS/AeroKit', '--workspace-changed']
```

`exec-on-workspace-change` runs a single command, so if you already use it
(e.g. for SketchyBar), chain AeroKit into the same shell string:

```toml
exec-on-workspace-change = ['/bin/bash', '-c', 'sketchybar --trigger aerospace_workspace_change FOCUSED=$AEROSPACE_WORKSPACE; /Applications/AeroKit.app/Contents/MacOS/AeroKit --workspace-changed']
```

## Requirements

- macOS 14 (Sonoma) or later
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) installed and running
  (`brew install --cask nikitabobko/tap/aerospace`)
- **Screen Recording** permission for window previews (the app works without it,
  minus previews)

## Install

With Homebrew (signed & notarized universal build):

```sh
brew install --cask jomatsu/tap/aerokit
```

Or build and install from source:

```sh
git clone https://github.com/jomatsu/aerokit.git
cd aerokit/packages/app
scripts/install-app.sh
```

The from-source install builds a release binary and wraps it into
`~/Applications/AeroKit.app`. Either way, on first launch the app registers
itself as a login item (System Settings › General › Login Items), toggleable
from the settings window.

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
