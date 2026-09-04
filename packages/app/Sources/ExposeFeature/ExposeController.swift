import AeroKitCore
import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

private let log = AppLog(category: "expose")

/// What one overlay presentation shows: the focused workspace's windows
/// (mission-control-like) or the focused app's windows from every workspace
/// (app-exposé-like).
enum ExposeScope {
    case workspace
    case app
}

/// Narrow test/production seams for WindowServer reads, overlay effects, and
/// physical input. Public construction still wires the live overlay, capturer,
/// and digit tap.
@MainActor
struct ExposeControllerHooks {
    var windowBounds: @Sendable () -> [CGWindowID: CGRect]
    var resolveScreen: (Int?) -> NSScreen?
    var isVisible: () -> Bool
    var show: (ExposeSession, NSScreen, Bool, ExposeOverlayMotion.Edge) -> Void
    var hide: () -> Void
    var beginEntry: () -> Void
    var isAccessibilityGranted: () -> Bool
    var startDigitTap: () -> Bool
    var stopDigitTap: () -> Void
    var scheduleEntryDeadline: (Int, @escaping @MainActor () -> Void) -> Void
    /// Fires after the off-main query returns, before the epoch guard, so a
    /// superseded load can be observed without sleeping.
    var presentationQueryFinished: () -> Void
    var capturesPreviews: Bool

    static func live(
        overlay: ExposeOverlay,
        capturer: WindowImageCapturer,
        interceptor: ExposeDigitInterceptor
    ) -> ExposeControllerHooks {
        ExposeControllerHooks(
            windowBounds: { capturer.windowBoundsByID() },
            resolveScreen: { PresentationScreenResolver.screen(for: $0) },
            isVisible: { overlay.isVisible },
            show: { session, screen, showsGroupingHint, edge in
                overlay.show(
                    session: session,
                    on: screen,
                    showsGroupingHint: showsGroupingHint,
                    slidesFrom: edge
                )
            },
            hide: { overlay.hide() },
            beginEntry: { overlay.beginEntry() },
            isAccessibilityGranted: { AccessibilityPermission.isGranted },
            startDigitTap: { interceptor.start() },
            stopDigitTap: { interceptor.stop() },
            scheduleEntryDeadline: { milliseconds, work in
                Task {
                    try? await Task.sleep(for: .milliseconds(milliseconds))
                    work()
                }
            },
            presentationQueryFinished: {},
            capturesPreviews: true
        )
    }
}

/// Wires the exposé hotkeys, the AeroSpace CLI, the capture pipeline, and the
/// overlay into the toggle-overview-click-to-focus loop.
@MainActor
public final class ExposeController {
    private let client: AeroSpaceClient
    private let capturer: WindowImageCapturer
    private let iconResolver = AppIconResolver()
    private let hotKeyCenter: HotKeyCenter
    private let preferences: ExposePreferences
    private let settingsModel = ExposeSettingsModel()
    private let overlay: ExposeOverlay?
    private let digitInterceptor: ExposeDigitInterceptor
    private let hooks: ExposeControllerHooks

    private var session: ExposeSession?
    /// Scope of the most recent presentation request; kept even when the
    /// request produced no overlay (re-pressing then simply retries).
    private var requestedScope = ExposeScope.workspace
    private var presentTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    /// Bumped by every present/dismiss so a presentation that was superseded
    /// while waiting on the CLI can tell and drop its stale result.
    private var presentEpoch = 0
    private var warnedAccessibilityMissing = false
    private var cancellables: Set<AnyCancellable> = []

    /// The coordinator owns the shared trackpad monitor (only one can watch
    /// the pad) and re-evaluates it whenever this fires.
    public var onSwipePreferenceChanged: (() -> Void)?

    /// Snapshot lookup for the drag-to-workspace drop bar, injected by the
    /// coordinator (the switcher owns the snapshot store). Sendable so the
    /// presentation's background hop can load previews — a cold cache means
    /// per-workspace disk decodes that must not block the main actor.
    public var workspacePreview: @Sendable (String) -> NSImage? = { _ in nil }

    public var wantsSwipeGestures: Bool {
        preferences.threeFingerSwipe
    }

    /// True while an overview is visible or being loaded — the window
    /// switcher defers to it (the two fight over the same key events).
    public var isActive: Bool {
        hooks.isVisible() || presentTask != nil
    }

    /// True when the settings window should open on launch: ⌥-digit quick
    /// select is enabled (the default) but lacks the Accessibility grant it
    /// needs — the feature would otherwise silently do nothing — or a
    /// failed hotkey registration left an overview unreachable. Read after
    /// `start()` — that's what registers the hotkeys. The app shell
    /// aggregates every feature's flag.
    public var needsOnboarding: Bool {
        preferences.modifierQuickSelect && !AccessibilityPermission.isGranted
            || settingsModel.hotKeyErrorMessage != nil
            || settingsModel.appHotKeyErrorMessage != nil
    }

    public init(client: AeroSpaceClient, hotKeyCenter: HotKeyCenter, preferences: ExposePreferences) {
        let overlay = ExposeOverlay()
        let capturer = WindowImageCapturer()
        let interceptor = ExposeDigitInterceptor()
        self.client = client
        self.hotKeyCenter = hotKeyCenter
        self.preferences = preferences
        self.overlay = overlay
        self.capturer = capturer
        digitInterceptor = interceptor
        hooks = .live(overlay: overlay, capturer: capturer, interceptor: interceptor)
    }

    /// Test seam: WindowServer queries, overlay effects, and the digit tap
    /// can be replaced without changing the public initializer.
    init(
        client: AeroSpaceClient,
        hotKeyCenter: HotKeyCenter,
        preferences: ExposePreferences,
        hooks: ExposeControllerHooks
    ) {
        self.client = client
        self.hotKeyCenter = hotKeyCenter
        self.preferences = preferences
        overlay = nil
        capturer = WindowImageCapturer()
        digitInterceptor = ExposeDigitInterceptor()
        self.hooks = hooks
    }

    public func start() {
        overlay?.onCancel = { [weak self] in self?.dismiss() }
        overlay?.onActivate = { [weak self] index in self?.activate(index) }
        overlay?.onMove = { [weak self] move in self?.session?.move(move) }
        overlay?.onHover = { [weak self] index in self?.session?.select(index) }
        overlay?.onToggleGrouping = { [weak self] in self?.toggleGrouping() }
        overlay?.onCloseSelected = { [weak self] in self?.closeSelected() }
        overlay?.onMoveSelectedToWorkspace = { [weak self] workspace in
            self?.moveSelected(toWorkspace: workspace)
        }
        overlay?.onMoveToWorkspace = { [weak self] id, workspace in
            self?.moveWindow(id: id, toWorkspace: workspace)
        }
        overlay?.groupToggleKey = preferences.groupToggleCharacter
        digitInterceptor.onDigit = { [weak self] digit in self?.quickSelectDigit(digit) }

        settingsModel.onHotKeyRecordingChanged = { [weak self] isRecording in
            // Suspend the global triggers while recording so the chosen
            // combination reaches the recorder instead of toggling the overview.
            guard let self else { return }
            if isRecording {
                hotKeyCenter.unregister(.exposeToggle)
                hotKeyCenter.unregister(.exposeAppToggle)
            } else {
                registerHotKeys()
            }
        }

        registerHotKeys()
        observePreferences()
    }

    /// Settings pane embedded in the unified settings window.
    public func makeSettingsPane() -> some View {
        ExposeSettingsView(model: settingsModel, preferences: preferences)
    }

    public func toggle() {
        toggle(scope: .workspace)
    }

    public func toggleAppWindows() {
        toggle(scope: .app)
    }

    /// The other scope's hotkey while the overview is open switches scopes
    /// instead of dismissing, mirroring Mission Control vs App Exposé.
    private func toggle(scope: ExposeScope) {
        let isActive = hooks.isVisible() || presentTask != nil
        if isActive {
            dismiss()
            if scope == requestedScope {
                return
            }
        }
        requestedScope = scope
        present(scope: scope)
    }

    private func registerHotKeys() {
        registerWorkspaceHotKey()
        registerAppHotKey()
    }

    /// Unregister first so a changed spec replaces the live binding instead
    /// of silently keeping the old one; each role owns its error message.
    private func registerWorkspaceHotKey() {
        hotKeyCenter.unregister(.exposeToggle)
        settingsModel.hotKeyErrorMessage = registerHotKey(.exposeToggle, spec: preferences.hotKey)
    }

    private func registerAppHotKey() {
        hotKeyCenter.unregister(.exposeAppToggle)
        settingsModel.appHotKeyErrorMessage = registerHotKey(.exposeAppToggle, spec: preferences.appHotKey)
    }

    /// Returns the user-facing error message, nil on success.
    private func registerHotKey(_ role: HotKeyRole, spec: HotKeySpec) -> String? {
        do {
            try hotKeyCenter.register(
                role,
                keyCode: UInt32(spec.keyCode),
                modifiers: spec.carbonModifiers
            )
            return nil
        } catch {
            log.error("exposé hotkey \(spec.displayKeys.joined()) registration failed: \(error)")
            return spec.registrationFailureMessage
        }
    }

    private func observePreferences() {
        preferences.$hotKey.dropFirst()
            .sink { [weak self] _ in self?.registerWorkspaceHotKey() }
            .store(in: &cancellables)
        preferences.$appHotKey.dropFirst()
            .sink { [weak self] _ in self?.registerAppHotKey() }
            .store(in: &cancellables)
        preferences.$groupToggleKey.dropFirst()
            .sink { [weak self] key in self?.overlay?.groupToggleKey = key.first ?? "0" }
            .store(in: &cancellables)
        preferences.$threeFingerSwipe.dropFirst()
            .sink { [weak self] _ in self?.onSwipePreferenceChanged?() }
            .store(in: &cancellables)
    }

    // MARK: - Presentation

    private func present(scope: ExposeScope) {
        presentEpoch += 1
        let epoch = presentEpoch
        presentTask = Task { [weak self] in
            await self?.runPresentation(epoch: epoch, scope: scope)
        }
    }

    private func runPresentation(epoch: Int, scope: ExposeScope) async {
        let client = client
        let windowBounds = hooks.windowBounds
        let preview = workspacePreview
        // The context helpers run off the main actor and route each blocking
        // CLI round trip through BlockingWork; the WindowServer queries stay
        // inline. A wedged server can't pin a cooperative-pool thread.
        let context: ExposePresentationLoader.PresentationContext? = switch scope {
        case .workspace:
            await ExposePresentationLoader.workspaceContext(
                client: client,
                windowBounds: windowBounds,
                preview: preview
            )
        case .app:
            await ExposePresentationLoader.appContext(
                client: client,
                windowBounds: windowBounds,
                preview: preview
            )
        }
        hooks.presentationQueryFinished()

        guard epoch == presentEpoch else {
            return
        }
        presentTask = nil
        guard let context, let screen = hooks.resolveScreen(context.snapshot.screenNumber) else {
            return
        }

        let windows = WindowOrdering.spatial(context.snapshot.windows, bounds: context.bounds)
        let session = ExposeSession(
            windows: windows,
            containerAspect: screen.frame.width / max(screen.frame.height, 1),
            bounds: context.bounds,
            focusedWindowID: context.focusedWindowID,
            icons: icons(for: windows),
            groupByApp: scope == .workspace && preferences.groupByApp,
            workspaceTargets: context.workspaceTargets,
            workspacePreviews: context.workspacePreviews
        )
        self.session = session
        hooks.show(
            session,
            screen,
            scope == .workspace && preferences.showGroupToggleHint,
            // The motion continues the gesture that owns each scope: the
            // workspace overview rises after a swipe up, app exposé descends
            // after a swipe down — also from hotkeys, so each scope keeps a
            // recognizable signature.
            scope == .workspace ? .bottom : .top
        )
        // The panel is up but transparent; the entry cascade waits for the
        // fast capture pass so the rows rise with real window pictures, not
        // icon placeholders that pop into images mid-animation. A deadline
        // caps the wait — better a rare placeholder than a laggy gesture.
        if hooks.capturesPreviews {
            startCaptures(session: session, bounds: context.bounds, screen: screen) { [weak self] in
                self?.hooks.beginEntry()
            }
        }
        let beginEntry = hooks.beginEntry
        hooks.scheduleEntryDeadline(120) { [weak self] in
            guard let self, epoch == presentEpoch else {
                return
            }
            beginEntry()
        }

        startDigitInterceptorIfEnabled()
    }

    private func startDigitInterceptorIfEnabled() {
        guard preferences.modifierQuickSelect else {
            return
        }
        guard hooks.isAccessibilityGranted() else {
            if !warnedAccessibilityMissing {
                warnedAccessibilityMissing = true
                log.error("option+digit quick select is on but Accessibility access is missing")
            }
            return
        }
        if !hooks.startDigitTap() {
            log.error("could not install the option+digit event tap")
        }
    }

    private func icons(for windows: [ExposeWindow]) -> [CGWindowID: NSImage] {
        var icons: [CGWindowID: NSImage] = [:]
        for window in windows {
            if let icon = iconResolver.icon(forBundleIdentifier: window.bundleIdentifier, name: window.appName) {
                icons[window.id] = icon
            }
        }
        return icons
    }

    // MARK: - Captures

    /// `onInitialCaptures` fires on the main actor once the fast capture
    /// pass has delivered everything it could — the cue that the overlay's
    /// tiles are as pictorial as they are going to quickly get. Skipped if
    /// the presentation was dismissed (cancellation) so a stale session
    /// can't start a newer overlay's entry.
    private func startCaptures(
        session: ExposeSession,
        bounds: [CGWindowID: CGRect],
        screen: NSScreen,
        onInitialCaptures: @escaping @MainActor () -> Void
    ) {
        let cell = TileGeometry.cellSize(
            container: screen.frame.size,
            grid: session.grid,
            gap: TileMetrics.gap,
            margin: TileMetrics.margin
        )
        let ids = session.tiles.map(\.window.id)
        let capturer = capturer
        let request = WindowPreviewCapture.Request(
            capturer: capturer,
            ids: ids,
            bounds: bounds,
            displayScale: screen.backingScaleFactor,
            maxDimension: max(cell.width, cell.height) * screen.backingScaleFactor
        )

        captureTask = Task { [weak session] in
            await WindowPreviewCapture.run(
                request,
                deliver: { id, image in
                    guard let image else {
                        return
                    }
                    session?.setImage(image, forWindow: id)
                },
                onInitialPass: onInitialCaptures
            )
        }
    }

    // MARK: - Selection

    /// `0` while the overview is open. Grouping only applies to the
    /// workspace scope — the app scope is a single app already — and the
    /// chosen mode becomes the default for the next presentation.
    private func toggleGrouping() {
        guard requestedScope == .workspace, let session else {
            return
        }
        session.toggleGrouping()
        preferences.groupByApp = session.isGroupedByApp
    }

    /// ⌥1–9 from the event tap, routed like typed keys so a digit chosen
    /// as the grouping toggle works there too.
    private func quickSelectDigit(_ digit: Int) {
        guard let character = String(digit).first else {
            return
        }
        let toggleKey = preferences.groupToggleCharacter
        if character == toggleKey {
            toggleGrouping()
        } else if let index = QuickSelect.index(for: character, excluding: toggleKey) {
            activate(index)
        }
    }

    private func activate(_ index: Int) {
        guard let session, session.tiles.indices.contains(index) else {
            return
        }
        let id = session.tiles[index].window.id
        dismiss()
        runInBackground(failureLabel: "focusing window \(id)") {
            try $0.focusWindow(id: id)
        }
    }

    // MARK: - Window operations

    /// The keyboard operations' subject; nil while the overview is closed
    /// or the selection points at nothing.
    private var selectedWindowID: CGWindowID? {
        guard let session, session.tiles.indices.contains(session.selectedIndex) else {
            return nil
        }
        return session.tiles[session.selectedIndex].id
    }

    /// ⌘W: close the selected window. The overview stays up for the next
    /// operation; only the closed window's tile leaves.
    private func closeSelected() {
        guard let id = selectedWindowID else {
            return
        }
        removeWindow(id: id, failureLabel: "closing window \(id)") {
            try $0.closeWindow(id: id)
        }
    }

    /// ⇧1–9: send the selected window to the workspace named by the digit.
    private func moveSelected(toWorkspace workspace: String) {
        guard let id = selectedWindowID else {
            return
        }
        moveWindow(id: id, toWorkspace: workspace)
    }

    /// Shared by the keyboard and the drag-and-drop paths. A move to the
    /// window's own workspace is a no-op so a sloppy drop doesn't eat the
    /// tile. With "follow moved window" on, the overview closes and the
    /// move switches to the destination workspace; off, the overview stays
    /// up for the next operation.
    private func moveWindow(id: CGWindowID, toWorkspace workspace: String) {
        guard let session, let tile = session.tiles.first(where: { $0.id == id }),
              tile.window.workspace != workspace
        else {
            return
        }
        if preferences.followMovedWindow {
            dismiss()
            runInBackground(failureLabel: "moving window \(id) to \(workspace)") {
                try $0.summonWindow(id: id, toWorkspace: workspace)
            }
        } else {
            removeWindow(id: id, failureLabel: "moving window \(id) to \(workspace)") {
                try $0.moveWindow(id: id, toWorkspace: workspace)
            }
        }
    }

    /// Optimistic removal in the `activate` mold: the tile leaves and the
    /// grid re-flows immediately, the command runs fire-and-forget. A failed
    /// command leaves a missing tile, which the next presentation corrects.
    private func removeWindow(
        id: CGWindowID,
        failureLabel: String,
        command: @escaping @Sendable (AeroSpaceClient) throws -> Void
    ) {
        guard let session else {
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 1)) {
            session.removeTile(windowID: id)
        }
        if session.tiles.isEmpty {
            dismiss()
        }
        runInBackground(failureLabel: failureLabel, command)
    }

    /// Fire-and-forget AeroSpace command off the main actor, stderr-logged
    /// on failure — the mold every overlay-triggered command shares. The
    /// blocking round trip runs on BlockingWork so a wedged server can't
    /// starve the cooperative pool.
    private func runInBackground(
        failureLabel: String,
        _ command: @escaping @Sendable (AeroSpaceClient) throws -> Void
    ) {
        let client = client
        Task {
            await BlockingWork.run {
                do {
                    try command(client)
                } catch {
                    log.error("\(failureLabel) failed: \(error)")
                }
            }
        }
    }

    private func dismiss() {
        hooks.stopDigitTap()
        presentEpoch += 1
        presentTask?.cancel()
        presentTask = nil
        captureTask?.cancel()
        captureTask = nil
        hooks.hide()
        session = nil
    }
}

// MARK: - Trackpad swipes

public extension ExposeController {
    /// Mirrors the system gestures: from the normal view, swipe up opens
    /// the workspace overview (Mission Control) and swipe down opens app
    /// exposé. The reverse gesture returns to the normal view — down closes
    /// the overview, up closes app exposé — and repeating the opening
    /// gesture while its overlay is up does nothing, exactly as macOS does.
    func handleSwipe(_ direction: TrackpadSwipeMonitor.Direction) {
        guard preferences.threeFingerSwipe else {
            return
        }
        let isActive = hooks.isVisible() || presentTask != nil
        switch direction {
        case .up:
            if isActive {
                if requestedScope == .app {
                    dismiss()
                }
            } else {
                toggle(scope: .workspace)
            }
        case .down:
            if isActive {
                if requestedScope == .workspace {
                    dismiss()
                }
            } else {
                toggle(scope: .app)
            }
        }
    }

    /// Reflects the shared monitor's state in this feature's settings pane.
    func updateSwipeAvailability(monitorRunning: Bool) {
        settingsModel.swipeErrorMessage = TrackpadSwipeMonitor.unavailableMessage(
            gestureEnabled: preferences.threeFingerSwipe,
            monitorRunning: monitorRunning
        )
    }
}
