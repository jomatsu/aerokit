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
        // One background hop for the blocking CLI and WindowServer queries.
        let context = await Task.detached(priority: .userInitiated) { () -> PresentationContext? in
            switch scope {
            case .workspace:
                await Self.workspaceContext(client: client, capturer: capturer)
            case .app:
                await Self.appContext(client: client, capturer: capturer)
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
            groupByApp: scope == .workspace && preferences.groupByApp
        )
        self.session = session
        overlay.show(
            session: session,
            on: screen,
            showsGroupingHint: scope == .workspace && preferences.showGroupToggleHint
        )
        startCaptures(session: session, bounds: context.bounds, screen: screen)

        startDigitInterceptorIfEnabled()
    }

    private nonisolated static func workspaceContext(
        client: AeroSpaceClient,
        capturer: WindowImageCapturer
    ) async -> PresentationContext? {
        // The focused-window query only seeds the initial selection, so
        // run it concurrently instead of paying a second CLI round trip
        // before the overlay can show.
        async let focused = client.focusedWindow()
        guard let snapshot = loadSnapshot("workspace", { try client.focusedWorkspaceWindows() }) else {
            return nil
        }
        return await PresentationContext(
            snapshot: snapshot,
            focusedWindowID: focused?.id,
            bounds: capturer.windowBoundsByID()
        )
    }

    /// The CLI calls are sequential by necessity — the focused window's app
    /// determines which windows to list.
    private nonisolated static func appContext(
        client: AeroSpaceClient,
        capturer: WindowImageCapturer
    ) async -> PresentationContext? {
        // The bounds query talks to the WindowServer, not the CLI, so it can
        // overlap the dependent CLI round trips.
        async let bounds = capturer.windowBoundsByID()
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
            bounds: bounds
        )
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

    private func startCaptures(session: ExposeSession, bounds: [CGWindowID: CGRect], screen: NSScreen) {
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

            guard !missed.isEmpty, !Task.isCancelled else {
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

        let client = client
        Task.detached(priority: .userInitiated) {
            do {
                try client.focusWindow(id: id)
            } catch {
                fputs("AeroKit: focusing window \(id) failed: \(error)\n", stderr)
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

extension ExposeController {
    /// Mirrors the system gestures: swipe up opens (or switches to) the
    /// workspace overview, swipe down opens app exposé when nothing is
    /// shown and otherwise closes whatever is open. Horizontal swipes
    /// belong to the workspace switcher and are ignored here.
    public func handleSwipe(_ direction: TrackpadSwipeMonitor.Direction) {
        guard preferences.threeFingerSwipe else {
            return
        }
        let isActive = overlay.isVisible || presentTask != nil
        switch direction {
        case .up:
            guard !(isActive && requestedScope == .workspace) else {
                return
            }
            toggle(scope: .workspace)
        case .down:
            if isActive {
                dismiss()
            } else {
                toggle(scope: .app)
            }
        case .left, .right:
            break
        }
    }

    /// Reflects the shared monitor's state in this feature's settings pane.
    public func updateSwipeAvailability(monitorRunning: Bool) {
        settingsModel.swipeErrorMessage = TrackpadSwipeMonitor.unavailableMessage(
            gestureEnabled: preferences.threeFingerSwipe,
            monitorRunning: monitorRunning
        )
    }
}
