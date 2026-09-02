import AeroKitCore
import AppKit
import Carbon
import Combine
import Foundation
import SwiftUI

private let log = AppLog(category: "window-switcher")

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
    private let hotKeyCenter: HotKeyCenter
    private let preferences: ExposePreferences
    private let capturer = WindowImageCapturer()
    private let iconResolver = AppIconResolver()
    private let overlay = WindowSwitcherOverlay()
    private let settingsModel = WindowSwitcherSettingsModel()

    private var interceptor: WindowCycleInterceptor?
    private var dismissor: HoldToCommitDismiss?
    private var session: WindowCycleSession?
    private var presentTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    /// Bumped by every open/dismiss so a presentation superseded while
    /// waiting on the CLI can tell and drop its stale result.
    private var presentEpoch = 0
    private var cancellables: Set<AnyCancellable> = []

    public var isActive: Bool {
        overlay.isVisible
    }

    /// True when the settings window should open on launch: the switcher
    /// is enabled but its hotkey lost registration, leaving it unreachable.
    public var needsOnboarding: Bool {
        preferences.windowSwitchEnabled && settingsModel.hotKeyErrorMessage != nil
    }

    public init(client: AeroSpaceClient, hotKeyCenter: HotKeyCenter, preferences: ExposePreferences) {
        self.client = client
        self.hotKeyCenter = hotKeyCenter
        self.preferences = preferences
    }

    public func start() {
        overlay.onCancel = { [weak self] in self?.cancel() }
        overlay.keyHandler = { [weak self] event in
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
        guard !overlay.isVisible else {
            session?.move(initial)
            return
        }
        // Launch hotkeys unregistered while the strip is open: without the
        // event tap, Carbon would re-fire on key repeats instead of letting
        // them reach the panel.
        unregisterHotKeys()

        presentEpoch += 1
        let epoch = presentEpoch
        presentTask = Task { [weak self] in
            await self?.present(epoch: epoch, initial: initial)
        }
    }

    private func present(epoch: Int, initial: SelectionMove) async {
        let client = client
        let context: (snapshot: WorkspaceSnapshot, focusedID: CGWindowID?)? = await BlockingWork.run {
            guard let snapshot = try? client.focusedWorkspaceWindows(), !snapshot.windows.isEmpty else {
                return nil
            }
            return (snapshot, client.focusedWindow()?.id)
        }
        let stacking = await capturer.onScreenWindowIDsFrontToBack()

        guard epoch == presentEpoch else {
            return
        }
        presentTask = nil

        guard let context else {
            log.error("window switcher: no windows in the focused workspace")
            registerHotKeys()
            return
        }
        guard let screen = screen(for: context.snapshot.screenNumber) else {
            registerHotKeys()
            return
        }

        let ordered = WindowRecencyOrdering.ordered(
            windows: context.snapshot.windows,
            stacking: stacking,
            focusedID: context.focusedID
        )
        let icons = icons(for: ordered)
        let session = WindowCycleSession(windows: ordered, icons: icons)
        session.move(initial)
        self.session = session
        overlay.show(session: session, cardWidth: cardWidth(for: ordered.count, on: screen), on: screen)
        startCaptures(session: session, screen: screen)
        startInteractions()
    }

    private func commit() {
        guard overlay.isVisible, let session else {
            return
        }
        let id = session.selectedEntry?.window.id
        dismiss()
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
        guard overlay.isVisible else {
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
        overlay.hide()
        session = nil
        registerHotKeys()
    }

    // MARK: - Interaction

    private func startInteractions() {
        guard AccessibilityPermission.isGranted else {
            startFallbackDismissor()
            return
        }
        let interceptor = WindowCycleInterceptor(hotKey: preferences.windowSwitchHotKey)
        if interceptor.start() {
            interceptor.onMove = { [weak self] in self?.session?.move($0) }
            interceptor.onCancel = { [weak self] in self?.cancel() }
            interceptor.onCommit = { [weak self] in self?.commit() }
            self.interceptor = interceptor
        } else {
            log.error("could not install the window cycle event tap; falling back to panel keys")
            startFallbackDismissor()
        }
    }

    private func startFallbackDismissor() {
        let dismissor = HoldToCommitDismiss(
            triggerFlags: preferences.windowSwitchHotKey.modifierFlags,
            heldAtShow: true
        )
        dismissor.onModifierRelease = { [weak self] in self?.commit() }
        self.dismissor = dismissor
        dismissor.beginSession()
    }

    /// Panel key routing without the event tap: same pure rules the tap
    /// uses, plus re-arming the release detector.
    private func handleFallbackKey(_ event: NSEvent) -> Bool {
        dismissor?.noteKeyEvent(event)

        let kind: CycleKeyInput.Kind = switch event.keyCode {
        case preferences.windowSwitchHotKey.keyCode, KeyCode.tab:
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
            session?.move(.next)
        case .retreat:
            session?.move(.previous)
        case .cancel:
            cancel()
        case .commit, .swallow, .pass:
            break
        }
        return true
    }

    // MARK: - Captures

    private func startCaptures(session: WindowCycleSession, screen: NSScreen) {
        let displayScale = screen.backingScaleFactor
        let request = WindowPreviewCapture.Request(
            capturer: capturer,
            ids: session.entries.map(\.id),
            bounds: capturer.windowBoundsByID(),
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
                    let size = NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2)
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
        return max(90, min(WorkspaceCardMetrics.thumbSize.width, available / CGFloat(max(count, 1))))
    }

    private func screen(for screenNumber: Int?) -> NSScreen? {
        let screens = NSScreen.screens
        if let screenNumber, screens.indices.contains(screenNumber - 1) {
            return screens[screenNumber - 1]
        }
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? screens.first
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        hotKeyCenter.unregister(.windowCycleForward)
        hotKeyCenter.unregister(.windowCycleBackward)
        guard preferences.windowSwitchEnabled else {
            return
        }
        let spec = preferences.windowSwitchHotKey
        do {
            try hotKeyCenter.register(
                .windowCycleForward,
                keyCode: UInt32(spec.keyCode),
                modifiers: spec.carbonModifiers
            )
            try hotKeyCenter.register(
                .windowCycleBackward,
                keyCode: UInt32(spec.keyCode),
                modifiers: spec.carbonModifiers | UInt32(shiftKey)
            )
            settingsModel.hotKeyErrorMessage = nil
        } catch {
            log.error("window switcher hotkey registration failed: \(error)")
            settingsModel.hotKeyErrorMessage = spec.registrationFailureMessage
        }
    }

    private func unregisterHotKeys() {
        hotKeyCenter.unregister(.windowCycleForward)
        hotKeyCenter.unregister(.windowCycleBackward)
    }

    private func observePreferences() {
        preferences.$windowSwitchEnabled.dropFirst()
            .sink { [weak self] _ in self?.registerHotKeys() }
            .store(in: &cancellables)
        preferences.$windowSwitchHotKey.dropFirst()
            .sink { [weak self] _ in self?.registerHotKeys() }
            .store(in: &cancellables)
    }
}
