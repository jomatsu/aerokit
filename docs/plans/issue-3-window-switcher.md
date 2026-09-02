# Window Switcher (⌥Tab) — Implementation Plan

Issue: #3 (Alt-Tab-style window switching scoped to the active AeroSpace
workspace). Status: planned, not started. Decisions locked by the
maintainer are marked **[DECIDED]**.

## Decisions

- **[DECIDED] Default disabled.** The feature ships off; users enable it
  and record a hotkey in settings. Rationale: AeroSpace's stock config
  binds `alt-tab = workspace-back-and-forth`, so an on-by-default ⌥Tab
  would collide with Carbon registration out of the box.
- **[DECIDED] macOS ⌘Tab semantics**, implemented by sharing code with
  the existing workspace Switcher (not a bespoke interaction):
  - hotkey keyDown opens the strip and selects the next window
  - Tab taps advance (auto-repeat honored), ⇧Tab / ← → move backward /
    forward
  - releasing the trigger modifiers commits (same release-detection as
    the workspace Switcher: re-arm + 50 ms physical watchdog)
  - Esc cancels; every other key while the strip is open is swallowed
  - single window: strip flashes feedback, commit is a no-op
- **[DECIDED] Share code with the existing Switcher/Exposé** wherever the
  behavior is identical — see "Shared code" below.

## Architecture

Placement: `ExposeFeature` (Exposé already owns focused-workspace window
listing, the capture pipeline, and the interceptor precedent).
`ExposeController` stays under the split threshold; the new feature gets
its own controller.

State machine (`WindowSwitcherController`, `@MainActor`):

```
idle ──hotkey──▶ loading ──ok──▶ shown ──release──▶ committing ──▶ idle
                  │ │              │ ▲
                  │ └─release-     └─Tab/⇧Tab/←/→ move, Esc cancel
                  │  before-load
                  └─error/empty ──▶ idle        (commitOnLoad focuses idx 1)
```

`presentEpoch` guards stale loads (mold: `ExposeController`).

### Shared code (extract, then reuse)

| Extracted into AeroKitCore | Source | Consumers |
|---|---|---|
| `ScopedEventTap` (mask + consume-handler, re-enable-on-timeout, EventBox/assumeIsolated) | `ExposeDigitInterceptor` tap plumbing | digit interceptor (rebuild), `WindowCycleInterceptor` |
| `HoldToCommitDismiss` (local flagsChanged monitor + re-arm + 50 ms watchdog + `onModifierRelease`) | `SwiftUIOverlay` dismiss monitors | workspace `SwiftUIOverlay` (refactored onto it), window switcher panel |
| `SelectionMove` | already shared | window session `move(_:)` |
| `WorkspaceCardStyle` strip chrome (`workspaceStripPanel()`, `WorkspaceCardMetrics`, `WorkspaceCardThumbnail`) | already shared | strip view |

Event tap rules (`WindowCycleInterceptor`, taps
`keyDown | keyUp | flagsChanged`):

| Event | Rule | Consume |
|---|---|---|
| keyDown hotkey key, flags ⊇ trigger | advance (+⇧ retreat) | yes |
| keyDown ← / → | retreat / advance | yes |
| keyDown Esc | cancel | yes |
| any other keyDown/keyUp | swallow | yes |
| flagsChanged, trigger modifiers released | commit | no (never eat modifier state) |

No-Accessibility fallback: panel `keyHandler` receives Tab (proven by the
workspace switcher) + watchdog-only release detection; banner offers
Grant.

## File-level changes

New — AeroKitCore: `ScopedEventTap.swift`, `HoldToCommitDismiss.swift`.
New — ExposeFeature: `WindowRecencyOrdering.swift` (pure),
`CycleKeyRules.swift` (pure key→action), `WindowCycleInterceptor.swift`,
`WindowCycleSession.swift` (`@MainActor`, tiles + selectedIndex + move +
setImage), `WindowPreviewCapture.swift` (extracted from
`ExposeController.startCaptures`), `WindowSwitcherController.swift`
(`init(client:hotKeyCenter:preferences:)`, `start()`, `handle(_:)`,
`isActive`, `needsOnboarding`, `makeSettingsSection()`),
`WindowSwitcherOverlay.swift` (`OverlayPanel` host, fallback keyHandler,
resign→cancel), `WindowSwitcherStripView.swift`,
`WindowSwitcherSettingsView.swift`. Tests: `WindowRecencyOrderingTests`,
`CycleKeyRulesTests`, `WindowCycleSessionTests`.

Modified — AeroKitCore: `HotKeyCenter` gains
`windowCycleForward/Backward` roles; `WindowImageCapturer` gains
`onScreenWindowIDsFrontToBack()`. ExposeFeature: `ExposeDigitInterceptor`
rebuilt on `ScopedEventTap`; `ExposeController` accepts injected
`ExposePreferences`, delegates captures, exposes `isActive`.
SwitcherFeature: `SwiftUIOverlay` refactored onto `HoldToCommitDismiss`
(behavior-preserving). App: coordinator wiring + dispatch cases +
onboarding aggregation; README.

UI: strip family (`WorkspaceCardStyle`), card = static snapshot thumbnail
+ icon scrim + title; cards shrink to fit, no scroll (v1).

## Ordering (pseudocode)

```
stacking = CGWindowList(onScreenOnly | excludeDesktopElements).ids   // front→back
aero     = client.focusedWorkspaceWindows().windows                  // authoritative
ordered  = stacking.compactMap { byID[$0] }                          // drops parked windows
ordered += aero.filter { !ordered.contains($0) }                     // minimized etc.
rotate focused window (client.focusedWindow()?.id) to index 0
index 1 = preselected                                                // ⌘Tab behavior
```

## Edge cases

| Case | Behavior |
|---|---|
| Single window | strip + feedback; commit no-op |
| Zero windows / CLI error | no overlay, log, hotkeys restored |
| Release before load | `commitOnLoad` focuses index 1 |
| Window vanishes mid-cycle | static list; focus failure logged (v1) |
| Fullscreen apps | native-fullscreen windows absent (not in the workspace); panel via `.fullScreenAuxiliary` |
| Multi-monitor | `snapshot.screenNumber` → NSScreen (AeroSpace focused monitor) |
| AeroSpace down | no-op + log; existing health banner covers settings |
| Re-trigger while open | launch hotkeys unregistered while open; tap treats it as advance |
| Exposé/Switcher already open | coordinator drops the role |
| Hotkey conflict (stock `alt-tab`) | registration failure → banner + onboarding; feature is off by default |
| No Accessibility | panel-key fallback + watchdog; Grant banner |
| External workspace change while open | cancel (matches workspace Switcher) |

## Test plan (pure XCTest)

- `WindowRecencyOrderingTests`: stacking filter, off-list append,
  focused-rotate, duplicate ids
- `CycleKeyRulesTests`: advance/retreat/arrows/esc/swallow,
  flagsChanged-commit, never-consumed, ⇧-alone-doesn't-hold
- `WindowCycleSessionTests`: preselect index 1, single-window, wrap,
  setImage-unknown-window

## Milestones

1. **Refactor, no behavior change** — `ScopedEventTap` +
   digit-interceptor rebuild; `HoldToCommitDismiss` + `SwiftUIOverlay`
   migration; `WindowPreviewCapture` extraction;
   `onScreenWindowIDsFrontToBack`; `WindowRecencyOrdering` + tests.
2. **Feature core** — roles, preferences (default off), session, rules,
   interceptor, controller, overlay/strip, coordinator wiring.
   Manual: cycle, release, Esc, quick tap, single window.
3. **Settings + docs** — settings section, onboarding, README, fallback
   polish, capture placeholders.

## Issue #3 reply draft

> Thanks for the detailed proposal — this fits the roadmap, and you
> identified exactly the gap: generic Alt-Tab tools mix in AeroSpace's
> off-screen-parked windows because all workspaces share one macOS Space.
>
> The plan is settled: a ⌥Tab-style strip over the focused workspace's
> windows with macOS ⌘Tab semantics (Tab taps advance including
> auto-repeat, ⇧Tab reverses, releasing the modifiers commits, Esc
> cancels), ordering by `CGWindowList` stacking order filtered to the
> workspace — a recency proxy without focus-history tracking. It shares
> the interaction machinery with the existing workspace Switcher
> (release-to-commit detection, selection movement) and the Exposé
> snapshot pipeline, and ships **disabled by default** since AeroSpace's
> stock config already binds alt-tab; you'd enable it and pick a hotkey
> in settings.
>
> First version scope: static snapshot previews, focused workspace only,
> configurable hotkey. If you'd like to contribute, the first slice is a
> behavior-preserving refactor (event-tap + release-detection extraction)
> — happy to walk through the architecture here.
