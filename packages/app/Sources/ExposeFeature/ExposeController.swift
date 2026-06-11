import AeroKitCore
import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Wires the exposé hotkey, the AeroSpace CLI, the capture pipeline, and the
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
    private var presentTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    /// Bumped by every present/dismiss so a presentation that was superseded
    /// while waiting on the CLI can tell and drop its stale result.
    private var presentEpoch = 0
    private var warnedAccessibilityMissing = false
    private var cancellables: Set<AnyCancellable> = []

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
        digitInterceptor.onDigit = { [weak self] digit in self?.activate(digit - 1) }

        settingsModel.onHotKeyRecordingChanged = { [weak self] isRecording in
            // Suspend the global trigger while recording so the chosen
            // combination reaches the recorder instead of toggling the overview.
            guard let self else { return }
            if isRecording {
                hotKeyCenter.unregister(.exposeToggle)
            } else {
                registerHotKey()
            }
        }

        registerHotKey()
        observePreferences()
    }

    /// Settings pane embedded in the unified settings window.
    public func makeSettingsPane() -> some View {
        ExposeSettingsView(model: settingsModel, preferences: preferences)
    }

    public func toggle() {
        if overlay.isVisible || presentTask != nil {
            dismiss()
        } else {
            present()
        }
    }

    private func registerHotKey() {
        let spec = preferences.hotKey
        do {
            try hotKeyCenter.register(
                .exposeToggle,
                keyCode: UInt32(spec.keyCode),
                modifiers: spec.carbonModifiers
            )
            settingsModel.hotKeyErrorMessage = nil
        } catch {
            fputs("AeroKit: exposé hotkey registration failed: \(error)\n", stderr)
            settingsModel.hotKeyErrorMessage =
                "Could not register \(spec.displayKeys.joined()) as the global hotkey. "
                    + "Another app may already use it — record a different shortcut above."
        }
    }

    private func observePreferences() {
        preferences.$hotKey.dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                hotKeyCenter.unregister(.exposeToggle)
                registerHotKey()
            }
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

    private func present() {
        presentEpoch += 1
        let epoch = presentEpoch
        presentTask = Task { [weak self] in
            await self?.runPresentation(epoch: epoch)
        }
    }

    private func runPresentation(epoch: Int) async {
        let client = client
        let capturer = capturer
        // One background hop for the blocking CLI and WindowServer queries.
        let context = await Task.detached(priority: .userInitiated) { () -> PresentationContext? in
            // The focused-window query only seeds the initial selection, so
            // run it concurrently instead of paying a second CLI round trip
            // before the overlay can show.
            async let focusedWindowID = client.focusedWindowID()
            let snapshot: WorkspaceSnapshot
            do {
                snapshot = try client.focusedWorkspaceWindows()
            } catch {
                fputs("AeroKit: listing workspace windows failed: \(error)\n", stderr)
                return nil
            }
            guard !snapshot.windows.isEmpty else {
                return nil
            }
            return await PresentationContext(
                snapshot: snapshot,
                focusedWindowID: focusedWindowID,
                bounds: capturer.windowBoundsByID()
            )
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
            icons: icons(for: windows)
        )
        self.session = session
        overlay.show(session: session, on: screen)
        startCaptures(session: session, bounds: context.bounds, screen: screen)

        startDigitInterceptorIfEnabled()
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
