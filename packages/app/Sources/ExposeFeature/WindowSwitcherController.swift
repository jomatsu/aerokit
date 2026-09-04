import AeroKitCore
import AppKit
import Carbon
import Combine
import Foundation
import SwiftUI

private let log = AppLog(category: "window-switcher")

/// Narrow seams for WindowServer reads, overlay effects, and the same
/// input/hotkey surfaces production uses. Public construction still wires
/// the live overlay, capturer, interceptor, and Carbon center.
@MainActor
struct WindowSwitcherControllerHooks {
    var windowBounds: @Sendable () -> [CGWindowID: CGRect]
    var stacking: @Sendable () -> [CGWindowID]
    var resolveScreen: (Int?) -> NSScreen?
    var isVisible: () -> Bool
    var show: (WindowCycleSession, CGFloat, NSScreen) -> Void
    var hide: () -> Void
    var modifiersHeld: (NSEvent.ModifierFlags) -> Bool
    var isAccessibilityGranted: () -> Bool
    var makeCycleTap: (HotKeySpec) -> any WindowCycleTapping
    var makeHoldDismiss: (NSEvent.ModifierFlags, Bool) -> any HoldToCommitDismissing
    var hotKeys: any WindowSwitcherHotKeyRegistering
    var scheduleQuickTapCommit: (TimeInterval, @escaping () -> Void) -> Void
    /// Fires after the off-main query returns, before the epoch guard, so a
    /// superseded load can be observed without sleeping.
    var presentationQueryFinished: () -> Void
    var capturesPreviews: Bool

    static func live(
        overlay: WindowSwitcherOverlay,
        capturer: WindowImageCapturer,
        hotKeys: any WindowSwitcherHotKeyRegistering
    ) -> WindowSwitcherControllerHooks {
        WindowSwitcherControllerHooks(
            windowBounds: { capturer.windowBoundsByID() },
            stacking: { capturer.onScreenWindowIDsFrontToBack() },
            resolveScreen: { PresentationScreenResolver.screen(for: $0) },
            isVisible: { overlay.isVisible },
            show: { session, cardWidth, screen in
                overlay.show(session: session, cardWidth: cardWidth, on: screen)
            },
            hide: { overlay.hide() },
            modifiersHeld: { HoldToCommitDismiss.modifiersPhysicallyHeld($0) },
            isAccessibilityGranted: { AccessibilityPermission.isGranted },
            makeCycleTap: { WindowSwitcherInteractions.cycleTap(hotKey: $0) },
            makeHoldDismiss: { WindowSwitcherInteractions.holdDismiss(triggerFlags: $0, heldAtShow: $1) },
            hotKeys: hotKeys,
            scheduleQuickTapCommit: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    work()
                }
            },
            presentationQueryFinished: {},
            capturesPreviews: true
        )
    }
}

/// ⌥Tab-style cycling over the focused AeroSpace workspace's windows:
/// hold the hotkey, tap the key to cycle (auto-repeat advances), release
/// to commit. macOS ⌘Tab semantics on the workspace Switcher's
/// interaction model, sharing the Exposé capture pipeline; the strip's
/// order comes from the system stacking order filtered to the workspace.
///
/// Ships disabled — AeroSpace's stock config already binds alt-tab, so
/// enabling is an explicit choice made in settings.
@MainActor
public final class WindowSwitcherController {
    private let client: AeroSpaceClient
    private let preferences: ExposePreferences
    private let capturer: WindowImageCapturer
    private let iconResolver = AppIconResolver()
    private let overlay: WindowSwitcherOverlay?
    private let settingsModel = WindowSwitcherSettingsModel()
    private let hooks: WindowSwitcherControllerHooks

    private var interceptor: (any WindowCycleTapping)?
    private var dismissor: (any HoldToCommitDismissing)?
    private var session: WindowCycleSession?
    /// Net cycle moves tapped while the presentation was still loading;
    /// applied to the session the moment it lands (grok: a fast double-tap
    /// across a slow CLI must skip two windows, not one).
    private var pendingMoves = 0
    private var presentTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    /// Bumped by every open/dismiss so a presentation superseded while
    /// waiting on the CLI can tell and drop its stale result.
    private var presentEpoch = 0
    /// Set when the trigger modifiers were released while the presentation
    /// was still loading (or in the hop before the tap existed): the strip
    /// still appears — a quick tap must flash feedback — then commits on
    /// the next runloop tick, matching the workspace Switcher.
    private var commitOnLoad = false
    private var cancellables: Set<AnyCancellable> = []

    /// Active while the strip is visible *or* a presentation is loading —
    /// the load window is exactly when the trigger can be released, the
    /// hook's echo can arrive, or a competing overlay can start.
    public var isActive: Bool {
        hooks.isVisible() || presentTask != nil
    }

    /// How many windows the strip shows. Recency order means the oldest
    /// windows past this cap stay reachable via the exposé instead.
    static let maxStripEntries = 12

    /// True when the settings window should open on launch: the switcher
    /// is enabled but its hotkey lost registration, leaving it unreachable.
    public var needsOnboarding: Bool {
        preferences.windowSwitchEnabled && settingsModel.hotKeyErrorMessage != nil
    }

    public init(client: AeroSpaceClient, hotKeyCenter: HotKeyCenter, preferences: ExposePreferences) {
        let overlay = WindowSwitcherOverlay()
        let capturer = WindowImageCapturer()
        self.client = client
        self.preferences = preferences
        self.capturer = capturer
        self.overlay = overlay
        hooks = .live(overlay: overlay, capturer: capturer, hotKeys: hotKeyCenter)
    }

    /// Test seam: WindowServer queries, overlay effects, and physical input
    /// can be replaced without changing the public initializer.
    init(
        client: AeroSpaceClient,
        preferences: ExposePreferences,
        hooks: WindowSwitcherControllerHooks
    ) {
        self.client = client
        self.preferences = preferences
        capturer = WindowImageCapturer()
        overlay = nil
        self.hooks = hooks
    }

    public func start() {
        overlay?.onCancel = { [weak self] in self?.cancel() }
        overlay?.keyHandler = { [weak self] event in
            self?.handleFallbackKey(event) ?? false
        }

        settingsModel.onHotKeyRecordingChanged = { [weak self] isRecording in
            // Suspend the global triggers while recording so the chosen
            // combination reaches the recorder instead of opening the strip.
            guard let self else { return }
            if isRecording {
                unregisterHotKeys()
            } else {
                registerHotKeys()
            }
        }

        observePreferences()
        registerHotKeys()
    }

    /// Settings section embedded in the unified settings window's Exposé
    /// pane; one preference store backs both features.
    public func makeSettingsSection() -> some View {
        WindowSwitcherSettingsView(model: settingsModel, preferences: preferences)
    }

    public func handle(_ role: HotKeyRole) {
        guard preferences.windowSwitchEnabled else {
            return
        }
        switch role {
        case .windowCycleForward:
            open(selecting: .next)
        case .windowCycleBackward:
            open(selecting: .previous)
        case .cycleForward, .cycleBackward, .escape, .exposeToggle, .exposeAppToggle:
            break
        }
    }

    /// The external workspace change surfaced by the coordinator (exec hook
    /// notification) invalidates the strip: its windows describe a
    /// workspace that is no longer in front.
    public func cancelIfActive() {
        guard isActive else {
            return
        }
        dismiss()
    }

    // MARK: - Open / close

    private func open(selecting initial: SelectionMove) {
        if hooks.isVisible() {
            session?.move(initial)
            return
        }
        if presentTask != nil {
            // A load is already in flight. On the fallback path Carbon is
            // still registered and consumed this repeat; count it so it
            // lands once the session arrives.
            pendingMoves += initial == .next ? 1 : -1
            return
        }

        commitOnLoad = false
        pendingMoves = 0
        // The tap must own the trigger key from here on — Carbon would only
        // double-fire — and if the modifiers were already released in the
        // dispatch hop before the tap existed, no flagsChanged will ever
        // arrive: flag the commit up front. The fallback path keeps Carbon
        // registered through the load (its repeats re-enter here and count
        // as pending moves instead of leaking to apps) and unregisters once
        // the panel is up.
        if !hooks.modifiersHeld(preferences.windowSwitchHotKey.modifierFlags) {
            commitOnLoad = true
        }
        startInteractions()
        if interceptor != nil {
            unregisterHotKeys()
        }

        presentTask?.cancel()
        presentEpoch += 1
        let epoch = presentEpoch
        presentTask = Task { [weak self] in
            await self?.present(epoch: epoch, initial: initial)
        }
    }

    private func present(epoch: Int, initial: SelectionMove) async {
        let client = client
        let stacking = hooks.stacking
        let bounds = hooks.windowBounds
        // Everything off-main in one BlockingWork hop: two CLI round trips
        // plus the WindowServer queries, which are synchronous and would
        // otherwise block the main actor.
        let context = await WindowSwitcherPresentationLoader.load(
            client: client,
            stacking: stacking,
            bounds: bounds
        )
        hooks.presentationQueryFinished()

        // A cancel during the load bumps the epoch; the cancelled task must
        // not resurrect a strip or re-register anything.
        guard epoch == presentEpoch, !Task.isCancelled else {
            return
        }
        presentTask = nil

        guard let context else {
            // The presentation is dead — the interactions started in open()
            // must go with it, or the tap keeps swallowing every keystroke
            // system-wide with no keyboard recovery.
            dismiss()
            return
        }
        guard let screen = hooks.resolveScreen(context.snapshot.screenNumber) else {
            dismiss()
            return
        }

        let session = makeSession(from: context, initial: initial, on: screen)
        self.session = session

        hooks.show(session, cardWidth(for: session.entries.count, on: screen), screen)
        // The fallback owns repeats via the panel from here; release Carbon.
        if interceptor == nil {
            unregisterHotKeys()
        }
        if hooks.capturesPreviews {
            startCaptures(session: session, screen: screen, bounds: context.bounds)
        }
        // Modifiers already released: still show (visual feedback) then
        // commit next tick so the strip can paint, matching SwiftUIOverlay.
        commitAfterShowingIfNeeded()
    }

    /// Quick-tap path: the strip is on screen, the trigger is already up,
    /// so commit on the next runloop turn rather than skipping `show()`.
    /// `presentEpoch` drops a commit whose presentation was cancelled or
    /// superseded before the tick lands.
    private func commitAfterShowingIfNeeded() {
        guard commitOnLoad else {
            return
        }
        commitOnLoad = false
        let epoch = presentEpoch
        // Quick-tap path: the strip is on screen, the trigger is already up,
        // so hold for ~100ms so the eye sees the feedback before committing,
        // matching the plan ("strip flashes feedback, commit is a no-op").
        hooks.scheduleQuickTapCommit(0.1) { [weak self] in
            guard let self, epoch == presentEpoch, hooks.isVisible() else {
                return
            }
            commit()
        }
    }

    /// Builds the cycling session: recency order capped so huge workspaces
    /// cannot overflow any fixed-width strip (the oldest windows stay
    /// reachable via the exposé) — the cap also respects the minimum
    /// card width that fits this screen — then the opening move and the
    /// cycle taps that arrived during the load (every one of them, not
    /// just their net direction).
    private func makeSession(
        from context: WindowSwitcherPresentationLoader.PresentationContext,
        initial: SelectionMove,
        on screen: NSScreen
    ) -> WindowCycleSession {
        let widthCap = max(
            1,
            Int((screen.visibleFrame.width - 32) / (56 + WorkspaceCardMetrics.cellSpacing))
        )
        let ordered = Array(
            WindowRecencyOrdering.ordered(
                windows: context.snapshot.windows,
                stacking: context.stacking,
                focusedID: context.focusedID
            )
            .prefix(min(Self.maxStripEntries, widthCap))
        )
        let icons = icons(for: ordered)
        let session = WindowCycleSession(windows: ordered, icons: icons)
        session.move(initial)
        let extra = abs(pendingMoves)
        if pendingMoves > 0 {
            for _ in 0 ..< extra {
                session.move(.next)
            }
        } else if pendingMoves < 0 {
            for _ in 0 ..< extra {
                session.move(.previous)
            }
        }
        pendingMoves = 0
        return session
    }

    private func commitRequest() {
        if hooks.isVisible() {
            commit()
        } else if presentTask != nil {
            commitOnLoad = true
        }
    }

    /// A cycle tap during the load lands on nothing yet — count it and
    /// apply it when the session arrives, so a fast double-tap across a
    /// slow CLI skips two windows, not one.
    private func move(_ move: SelectionMove) {
        if let session {
            session.move(move)
        } else if isActive {
            switch move {
            case .next, .right, .down:
                pendingMoves += 1
            case .previous, .left, .up:
                pendingMoves -= 1
            }
        }
    }

    private func commit() {
        guard hooks.isVisible(), let session else {
            return
        }
        let id = session.selectedEntry?.window.id
        dismiss()
        focus(id: id)
    }

    private func focus(id: CGWindowID?) {
        guard let id else {
            return
        }
        let client = client
        Task {
            await BlockingWork.run {
                do {
                    try client.focusWindow(id: id)
                } catch {
                    log.error("focusing window \(id) failed: \(error)")
                }
            }
        }
    }

    private func cancel() {
        guard isActive else {
            return
        }
        dismiss()
    }

    private func dismiss() {
        presentEpoch += 1
        presentTask?.cancel()
        presentTask = nil
        captureTask?.cancel()
        captureTask = nil
        interceptor?.stop()
        interceptor = nil
        dismissor?.endSession()
        dismissor = nil
        hooks.hide()
        session = nil
        pendingMoves = 0
        commitOnLoad = false
        registerHotKeys()
    }

    // MARK: - Interaction

    private func startInteractions() {
        // Never overwrite a live tap: its callback holds an unretained
        // pointer to it, and dropping the object without stopping the port
        // would leave the callback dangling.
        interceptor?.stop()
        interceptor = nil
        dismissor?.endSession()
        dismissor = nil

        guard hooks.isAccessibilityGranted() else {
            startFallbackDismissor()
            return
        }
        let interceptor = hooks.makeCycleTap(preferences.windowSwitchHotKey)
        if interceptor.start() {
            interceptor.onMove = { [weak self] in self?.move($0) }
            interceptor.onCancel = { [weak self] in self?.cancel() }
            interceptor.onCommit = { [weak self] in self?.commitRequest() }
            self.interceptor = interceptor
        } else {
            log.error("could not install the window cycle event tap; falling back to panel keys")
            startFallbackDismissor()
        }
    }

    private func startFallbackDismissor() {
        // heldAtShow is true by construction: this runs at open, and a
        // Carbon hotkey only fires with its modifiers held.
        let dismissor = hooks.makeHoldDismiss(preferences.windowSwitchHotKey.modifierFlags, true)
        dismissor.onModifierRelease = { [weak self] in self?.commitRequest() }
        self.dismissor = dismissor
        dismissor.beginSession()
    }

    /// Panel key routing without the event tap: same pure rules the tap
    /// uses, plus re-arming the release detector.
    private func handleFallbackKey(_ event: NSEvent) -> Bool {
        dismissor?.noteKeyEvent(event)

        let kind: CycleKeyInput.Kind = switch event.keyCode {
        case preferences.windowSwitchHotKey.keyCode:
            .hotKey
        case KeyCode.leftArrow:
            .leftArrow
        case KeyCode.rightArrow:
            .rightArrow
        case KeyCode.escape:
            .escape
        default:
            .other
        }
        let shifted = event.modifierFlags.contains(.shift)
        switch CycleKeyRules.action(for: .key(kind, shifted: shifted)) {
        case .advance:
            move(.next)
        case .retreat:
            move(.previous)
        case .cancel:
            cancel()
        case .commit, .swallow, .pass:
            break
        }
        return true
    }

    // MARK: - Captures

    private func startCaptures(
        session: WindowCycleSession,
        screen: NSScreen,
        bounds: [CGWindowID: CGRect]
    ) {
        let displayScale = screen.backingScaleFactor
        let request = WindowPreviewCapture.Request(
            capturer: capturer,
            ids: session.entries.map(\.id),
            bounds: bounds,
            displayScale: displayScale,
            maxDimension: session.entries.isEmpty
                ? 200 * displayScale
                : cardWidth(for: session.entries.count, on: screen) * 2 * displayScale
        )
        captureTask = Task { [weak session] in
            await WindowPreviewCapture.run(
                request,
                deliver: { id, image in
                    guard let cgImage = image, let session else {
                        return
                    }
                    let size = NSSize(
                        width: CGFloat(cgImage.width) / displayScale,
                        height: CGFloat(cgImage.height) / displayScale
                    )
                    session.setImage(NSImage(cgImage: cgImage, size: size), forWindow: id)
                },
                onInitialPass: {}
            )
        }
    }

    private func icons(for windows: [ExposeWindow]) -> [CGWindowID: NSImage] {
        var icons: [CGWindowID: NSImage] = [:]
        for window in windows {
            icons[window.id] = iconResolver.icon(
                forBundleIdentifier: window.bundleIdentifier,
                name: window.appName
            )
        }
        return icons
    }

    private func cardWidth(for count: Int, on screen: NSScreen) -> CGFloat {
        let spacing = WorkspaceCardMetrics.cellSpacing
        let available = screen.visibleFrame.width - 80 - spacing * CGFloat(max(count - 1, 0))
        return max(56, min(WorkspaceCardMetrics.thumbSize.width, available / CGFloat(max(count, 1))))
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        // While the strip (or its load) owns the trigger, re-registration
        // would make Carbon and the event tap both fire on the same repeat;
        // every exit path re-registers after dismiss.
        guard !isActive else {
            return
        }
        hooks.hotKeys.unregister(.windowCycleForward)
        hooks.hotKeys.unregister(.windowCycleBackward)
        guard preferences.windowSwitchEnabled else {
            settingsModel.hotKeyErrorMessage = nil
            return
        }
        let spec = preferences.windowSwitchHotKey
        do {
            try hooks.hotKeys.register(
                .windowCycleForward,
                keyCode: UInt32(spec.keyCode),
                modifiers: spec.carbonModifiers
            )
            try hooks.hotKeys.register(
                .windowCycleBackward,
                keyCode: UInt32(spec.keyCode),
                modifiers: spec.carbonModifiers | UInt32(shiftKey)
            )
            settingsModel.hotKeyErrorMessage = nil
        } catch {
            // Half a feature is worse than none: roll both roles back so a
            // partial registration can't fire while the banner shows.
            hooks.hotKeys.unregister(.windowCycleForward)
            hooks.hotKeys.unregister(.windowCycleBackward)
            log.error("window switcher hotkey registration failed: \(error)")
            settingsModel.hotKeyErrorMessage = spec.registrationFailureMessage
        }
    }

    private func unregisterHotKeys() {
        hooks.hotKeys.unregister(.windowCycleForward)
        hooks.hotKeys.unregister(.windowCycleBackward)
    }

    private func observePreferences() {
        preferences.$windowSwitchEnabled.dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                // Disabling mid-session must tear the strip/load down now,
                // not wait for a commit that may never come.
                if !enabled {
                    dismiss()
                }
                registerHotKeys()
            }
            .store(in: &cancellables)
        preferences.$windowSwitchHotKey.dropFirst()
            .sink { [weak self] _ in self?.registerHotKeys() }
            .store(in: &cancellables)
    }
}
