# AeroSwitcher

A native SwiftUI AeroSpace workspace switcher for macOS.

## Run

```sh
swift run AeroSwitcher
```

Press `Option + \`` to show the switcher. Press it again while the switcher is open to advance the selection. Press `Return` to switch to the selected workspace, `Esc` to dismiss, or a workspace key such as `1`, `2`, `Q`, `W`.

## Notes

- AeroSpace is read through `/opt/homebrew/bin/aerospace`.
- Workspace snapshots are loaded from `~/Pictures/AeroSpace Workspaces/current`.
- Snapshot refresh uses `~/dotfiles/scripts/aerospace-workspace-snapshot.sh --configured --current`.
- Hammerspoon is not required.

## Development

```sh
make bootstrap  # install SwiftFormat and SwiftLint through Homebrew
make format
make lint
make check
```
