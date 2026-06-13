import AeroKitCore
import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// What one overlay presentation shows: the focused workspace's windows
/// (mission-control-like) or the focused app's windows from every workspace
/// (app-exposé-like).
enum ExposeScope {
    case workspace
    case app
}

/// Wires the exposé hotkeys, the AeroSpace CLI, the capture pipeline, and the
/// overlay into the toggle-overview-click-to-focus loop.
@MainActor
public final class ExposeController {
    private let client: AeroSpaceClient
    private let capturer = WindowImageCapturer()
    private let iconResolver = AppIconResolver()
    private let hotKeyCenter: HotKeyCenter
    private let preferences: ExposePreferences
    private let settingsModel = ExposeSettingsModel()
    private let overlay = ExposeOverlay()
    private let digitInterceptor = ExposeDigitInterceptor()

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

    public init(client: AeroSpaceClient, hotKeyCenter: HotKeyCenter) {
        self.client = client
        self.hotKeyCenter = hotKeyCenter
        preferences = ExposePreferences()
    }

    public func start() {
        overlay.onCancel = { [weak self] in self?.dismiss() }
        overlay.onActivate = { [weak self] index in self?.activate(index) }
        overlay.onMove = { [weak self] move in self?.session?.move(move) }
        overlay.onHover = { [weak self] index in self?.session?.select(index) }
        overlay.onToggleGrouping = { [weak self] in self?.toggleGrouping() }
        overlay.onCloseSelected = { [weak self] in self?.closeSelected() }
        overlay.onMoveSelectedToWorkspace = { [weak self] workspace in
            self?.moveSelected(toWorkspace: workspace)
        }
        overlay.onMoveToWorkspace = { [weak self] id, workspace in
            self?.moveWindow(id: id, toWorkspace: workspace)
        }
        overlay.groupToggleKey = preferences.groupToggleCharacter
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
        let isActive = overlay.isVisible || presentTask != nil
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
            fputs("AeroKit: exposé hotkey \(spec.displayKeys.joined()) registration failed: \(error)\n", stderr)
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
            .sink { [weak self] key in self?.overlay.groupToggleKey = key.first ?? "0" }
            .store(in: &cancellables)
        preferences.$threeFingerSwipe.dropFirst()
            .sink { [weak self] _ in self?.onSwipePreferenceChanged?() }
            .store(in: &cancellables)
    }

    // MARK: - Presentation

    /// Everything the presentation needs from off-main queries: the
    /// workspace's windows, the focused window, and all window bounds.
    private struct PresentationContext {
        var snapshot: WorkspaceSnapshot
        var focusedWindowID: CGWindowID?
        var bounds: [CGWindowID: CGRect]
        var workspaceTargets: [WorkspaceTarget] = []
        var workspacePreviews: [String: NSImage] = [:]
    }

    private func present(scope: ExposeScope) {
        presentEpoch += 1
        let epoch = presentEpoch
        presentTask = Task { [weak self] in
            await self?.runPresentation(epoch: epoch, scope: scope)
        }
    }

    private func runPresentation(epoch: Int, scope: ExposeScope) async {
        let client = client
        let capturer = capturer
        let preview = workspacePreview
        // One background hop for the blocking CLI and WindowServer queries.
        let context = await Task.detached(priority: .userInitiated) { () -> PresentationContext? in
            switch scope {
            case .workspace:
                await Self.workspaceContext(client: client, capturer: capturer, preview: preview)
            case .app:
                await Self.appContext(client: client, capturer: capturer, preview: preview)
            }
        }.value

        guard epoch == presentEpoch else {
            return
        }
        presentTask = nil
        guard let context, let screen = screen(for: context.snapshot.screenNumber) else {
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
        overlay.show(
            session: session,
            on: screen,
            showsGroupingHint: scope == .workspace && preferences.showGroupToggleHint,
            // The motion continues the gesture that owns each scope: the
            // workspace overview rises after a swipe up, app exposé descends
            // after a swipe down — also from hotkeys, so each scope keeps a
            // recognizable signature.
            slidesFrom: scope == .workspace ? .bottom : .top
        )
        // The panel is up but transparent; the entry cascade waits for the
        // fast capture pass so the rows rise with real window pictures, not
        // icon placeholders that pop into images mid-animation. A deadline
        // caps the wait — better a rare placeholder than a laggy gesture.
        startCaptures(session: session, bounds: context.bounds, screen: screen) { [weak self] in
            self?.overlay.beginEntry()
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, epoch == presentEpoch else {
                return
            }
            overlay.beginEntry()
        }

        startDigitInterceptorIfEnabled()
    }

    private nonisolated static func workspaceContext(
        client: AeroSpaceClient,
        capturer: WindowImageCapturer,
        preview: @escaping @Sendable (String) -> NSImage?
    ) async -> PresentationContext? {
        // The focused-window query only seeds the initial selection, and
        // the drop-bar content is invisible until a drag starts, so both
        // run concurrently instead of paying extra CLI round trips before
        // the overlay can show.
        async let focused = client.focusedWindow()
        async let dropBar = loadDropBarContent(preview: preview) {
            try client.workspacesOnFocusedMonitor(includeEmpty: true)
        }
        guard let snapshot = loadSnapshot("workspace", { try client.focusedWorkspaceWindows() }) else {
            return nil
        }
        return await PresentationContext(
            snapshot: snapshot,
            focusedWindowID: focused?.id,
            bounds: capturer.windowBoundsByID(),
            workspaceTargets: dropBar.targets,
            workspacePreviews: dropBar.previews
        )
    }

    /// The CLI calls are sequential by necessity — the focused window's app
    /// determines which windows to list.
    private nonisolated static func appContext(
        client: AeroSpaceClient,
        capturer: WindowImageCapturer,
        preview: @escaping @Sendable (String) -> NSImage?
    ) async -> PresentationContext? {
        // The bounds query talks to the WindowServer, not the CLI, so it can
        // overlap the dependent CLI round trips; the drop-bar content is
        // invisible until a drag starts, so it loads concurrently too.
        async let bounds = capturer.windowBoundsByID()
        // The app's windows span monitors, so every workspace is a valid
        // drop target.
        async let dropBar = loadDropBarContent(preview: preview) { try client.listWorkspaces() }
        guard let focused = client.focusedWindow() else {
            fputs("AeroKit: app exposé: no focused window\n", stderr)
            return nil
        }
        guard var snapshot = loadSnapshot("app", {
            try client.appWindows(bundleIdentifier: focused.bundleIdentifier, pid: focused.pid)
        }) else {
            return nil
        }
        // The app's windows can span monitors; the overlay belongs on the
        // one hosting the focused window.
        snapshot.screenNumber = focused.screenNumber ?? snapshot.screenNumber
        return await PresentationContext(
            snapshot: snapshot,
            focusedWindowID: focused.id,
            bounds: bounds,
            workspaceTargets: dropBar.targets,
            workspacePreviews: dropBar.previews
        )
    }

    /// The drop bar's workspaces and their snapshot previews (workspaces
    /// the switcher has not snapshotted yet simply get a placeholder).
    /// Empty (logged) on CLI failure — the overlay shows no drop bar.
    private nonisolated static func loadDropBarContent(
        preview: @Sendable (String) -> NSImage?,
        _ list: () throws -> [(name: String, isFocused: Bool)]
    ) -> (targets: [WorkspaceTarget], previews: [String: NSImage]) {
        do {
            let targets = try list().map { WorkspaceTarget(name: $0.name, isFocused: $0.isFocused) }
            let previews = targets.reduce(into: [String: NSImage]()) { previews, target in
                previews[target.name] = preview(target.name)
            }
            return (targets, previews)
        } catch {
            fputs("AeroKit: listing workspaces failed: \(error)\n", stderr)
            return ([], [:])
        }
    }

    /// nil (logged) on CLI failure, nil on an empty listing — neither shows
    /// an overlay.
    private nonisolated static func loadSnapshot(
        _ label: String,
        _ list: () throws -> WorkspaceSnapshot
    ) -> WorkspaceSnapshot? {
        do {
            let snapshot = try list()
            return snapshot.windows.isEmpty ? nil : snapshot
        } catch {
            fputs("AeroKit: listing \(label) windows failed: \(error)\n", stderr)
            return nil
        }
    }

    private func startDigitInterceptorIfEnabled() {
        guard preferences.modifierQuickSelect else {
            return
        }
        guard AccessibilityPermission.isGranted else {
            if !warnedAccessibilityMissing {
                warnedAccessibilityMissing = true
                fputs("AeroKit: option+digit quick select is on but Accessibility access is missing\n", stderr)
            }
            return
        }
        if !digitInterceptor.start() {
            fputs("AeroKit: could not install the option+digit event tap\n", stderr)
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

    private func screen(for screenNumber: Int?) -> NSScreen? {
        let screens = NSScreen.screens
        if let screenNumber, screens.indices.contains(screenNumber - 1) {
            return screens[screenNumber - 1]
        }
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? screens.first
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
        let maxDimension = max(cell.width, cell.height) * screen.backingScaleFactor
        let displayScale = screen.backingScaleFactor
        let ids = session.tiles.map(\.window.id)
        let capturer = capturer

        captureTask = Task { [weak session] in
            var missed: [CGWindowID] = []
            await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
                for id in ids {
                    let pointSize = bounds[id]?.size
                    group.addTask {
                        let image = await CaptureLimiter.shared.withSlot { () -> CGImage? in
                            // A dismissed overview cancels its captures; once
                            // the slot frees up, skip the stale work instead
                            // of capturing for a session that is gone.
                            guard !Task.isCancelled else {
                                return nil
                            }
                            return capturer.captureImageFast(
                                windowID: id,
                                maxDimension: maxDimension,
                                pointSize: pointSize
                            )
                        }
                        return (id, image)
                    }
                }
                for await (id, image) in group {
                    if let image {
                        session?.setImage(image, forWindow: id)
                    } else {
                        missed.append(id)
                    }
                }
            }

            guard !Task.isCancelled else {
                return
            }
            onInitialCaptures()

            guard !missed.isEmpty else {
                return
            }
            await Self.captureFallback(
                capturer: capturer,
                ids: missed,
                displayScale: displayScale,
                maxDimension: maxDimension,
                session: session
            )
        }
    }

    /// ScreenCaptureKit pass for windows the fast path could not read.
    /// Sequential on purpose: the fallback is rare and SCScreenshotManager
    /// captures serialize in replayd anyway.
    private static func captureFallback(
        capturer: WindowImageCapturer,
        ids: [CGWindowID],
        displayScale: CGFloat,
        maxDimension: CGFloat,
        session: ExposeSession?
    ) async {
        guard let shareable = try? await capturer.shareableWindows() else {
            return
        }
        for id in ids {
            guard !Task.isCancelled, let window = shareable[id] else {
                continue
            }
            if let image = try? await capturer.captureImage(
                of: window,
                displayScale: displayScale,
                maxDimension: maxDimension
            ) {
                session?.setImage(image, forWindow: id)
            }
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
        runDetached(failureLabel: "focusing window \(id)") {
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
            runDetached(failureLabel: "moving window \(id) to \(workspace)") {
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
        runDetached(failureLabel: failureLabel, command)
    }

    /// Fire-and-forget AeroSpace command off the main actor, stderr-logged
    /// on failure — the mold every overlay-triggered command shares.
    private func runDetached(
        failureLabel: String,
        _ command: @escaping @Sendable (AeroSpaceClient) throws -> Void
    ) {
        let client = client
        Task.detached(priority: .userInitiated) {
            do {
                try command(client)
            } catch {
                fputs("AeroKit: \(failureLabel) failed: \(error)\n", stderr)
            }
        }
    }

    private func dismiss() {
        digitInterceptor.stop()
        presentEpoch += 1
        presentTask?.cancel()
        presentTask = nil
        captureTask?.cancel()
        captureTask = nil
        overlay.hide()
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
        let isActive = overlay.isVisible || presentTask != nil
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
