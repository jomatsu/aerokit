# AeroSwitcher

A native SwiftUI AeroSpace workspace switcher for macOS.

## Run

```sh
swift run AeroSwitcher
```

Press `Option + \`` to show the switcher. Press it again while the switcher is open to advance the selection. Press `Return` to switch to the selected workspace, `Esc` to dismiss, or a workspace key such as `1`, `2`, `Q`, `W`.

## Install

```sh
make install
```

Builds a release binary, bundles it as `~/Applications/AeroSwitcher.app`, and registers a launch agent so it starts at login. Grant Screen Recording permission to AeroSwitcher.app for workspace snapshots.

## Notes

- AeroSpace is read through `/opt/homebrew/bin/aerospace`.
- Workspace snapshots are captured in-app with ScreenCaptureKit (no external script or ImageMagick required) and stored under `~/Pictures/AeroSpace Workspaces/current`.
- Hammerspoon is not required.

## Development

```sh
make bootstrap  # install SwiftFormat and SwiftLint through Homebrew
make format
make lint
make check
```
