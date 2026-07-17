# AeroKit

One menu-bar app bundling the [AeroSpace](https://github.com/nikitabobko/AeroSpace)
companion tools. A single process, settings window, login item, and Screen
Recording grant covers every feature.

## Requirements

- macOS 14 (Sonoma) or later
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) installed and running —
  AeroKit talks to it through the `aerospace` CLI
- **Screen Recording** permission for window previews (everything else works
  without it)

## Features

### Switcher (default <kbd>⌥`</kbd>)

![Workspace Switcher](../../docs/images/aerokit-switcher.gif)

Cmd-Tab-style workspace switcher with snapshot previews. Hold the modifier
and tap the key to cycle; release to switch. Snapshots refresh in the
background and on demand.

### Exposé (default <kbd>⌥M</kbd>)

![Exposé](../../docs/images/aerokit-expose.gif)

Mission-Control-style overview of the focused workspace: live window
previews in a grid, laid out the way the windows sit on screen.
Click / <kbd>Return</kbd> / <kbd>1</kbd>–<kbd>9</kbd> (then <kbd>A</kbd>–<kbd>Z</kbd>)
focuses a window;
<kbd>Esc</kbd> or the hotkey dismisses. Windows are never moved — the
overview is a pure overlay, so it can't disturb the layout.

<kbd>0</kbd> (configurable) toggles grouping the overview by app: each
app's windows cluster into a card with the app's name instead of the
spatial layout. The last choice sticks and can also be set from the
settings window. If the chosen toggle key is one of the quick-select keys,
quick select simply skips it — the two can never collide.

### App Exposé (default <kbd>⌥A</kbd>)

The same overview scoped to the focused app: its windows from every
workspace in one grid. Activating a window on another workspace switches
there. Pressing one overview's hotkey while the other is open switches
scopes, like Mission Control vs App Exposé.

### Swipe (three-finger trackpad swipe)

![Trackpad Swipe](../../docs/images/aerokit-swipe.gif)

Swipe left or right with three fingers to switch between the focused
monitor's AeroSpace workspaces. A Raycast-style workspace strip briefly
appears at the bottom of the screen with the focused workspace
highlighted; consecutive swipes glide the highlight along the strip.
Natural direction (content follows the fingers), wrap-around, skipping
empty workspaces, and the strip itself are all configurable. Three-finger
swipes up/down still belong to Exposé.

All hotkeys are configurable from the settings window (menu bar icon →
Settings).

## Privacy

Snapshots are screenshots of your windows plus a manifest listing their
titles. They stay on your machine, unencrypted, under
`~/Library/Application Support/AeroKit/Workspace Snapshots` (older installs
are moved there automatically from `~/Pictures/AeroSpace Workspaces`).
Nothing ever leaves the machine.

To keep sensitive apps out of snapshots — password managers, banking — list
them under Settings → Switcher → Exclude Apps (app names or bundle IDs,
comma-separated). Excluded windows are never captured or listed in the
manifest.

Turning off automatic refresh in Settings stops all captures **and deletes
the stored previews**; the manual refresh button recreates them on demand.
`scripts/uninstall-app.sh --purge` removes them together with the app.

## Install

```sh
scripts/install-app.sh
```

Builds a release binary and wraps it into `~/Applications/AeroKit.app`. On
first launch AeroKit registers itself as a login item (System Settings ›
General › Login Items), which you can toggle from the settings window. The
installer also retires the pre-unification `AeroSwitcher.app` /
`AeroExpose.app` and their LaunchAgents; preferences carry over automatically.

Grant **Screen Recording** in the settings window when prompted — previews
need it (the apps still work without it, minus previews).

CLI entry points for scripting / AeroSpace keybindings:

```sh
AeroKit --open-settings
AeroKit --toggle-expose
AeroKit --toggle-app-expose
```

## Uninstall

```sh
scripts/uninstall-app.sh          # keeps snapshots & preferences
scripts/uninstall-app.sh --purge  # removes them too
```

Removes the app bundle and its login item; `--purge` also deletes stored
snapshots and AeroKit's preferences.

## Architecture

```
Sources/
  AeroKitCore      shared infrastructure: AeroSpace CLI client, process
                   runner, Carbon hotkeys, window capture (CGWindowList fast
                   path + ScreenCaptureKit fallback, process-wide concurrency
                   limit), permissions, login item, settings UI primitives
  SwitcherFeature  workspace switcher: overlay, snapshot engine & scheduler
  ExposeFeature    window overview: overlay, grid layout, live previews
  SwipeFeature     trackpad workspace switching: swipe → workspace ring
                   navigation, workspace strip HUD
  AeroKit          app shell: status bar, unified settings window, hotkey
                   dispatch, preference migration
```

## Development

```sh
swift build
swift test
```
