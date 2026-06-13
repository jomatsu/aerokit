import AeroKitCore
import AppKit
import ExposeFeature
import Foundation
import SwipeFeature
import SwitcherFeature

/// Owns the pieces every feature shares — the Carbon hotkey center, the
/// status bar item, the trackpad monitor, and the settings window — and
/// routes events to the switcher, exposé, and swipe controllers.
@MainActor
final class AppCoordinator {
    private let hotKeyCenter = HotKeyCenter()
    private let statusBar = StatusBarController()
    private let client: AeroSpaceClient
    private let switcher: SwitcherController
    private let expose: ExposeController
    private let swipe: SwipeController
    /// Shared because only one monitor can observe the trackpad: vertical
    /// swipes go to exposé, horizontal ones to the workspace switcher.
    private let swipeMonitor = TrackpadSwipeMonitor()
    private var settingsWindow: SettingsWindowController?
    private var settingsSummonTask: Task<Void, Never>?

    init() {
        PreferencesMigration.migrateIfNeeded()

        client = AeroSpaceClient(executablePath: AeroSpaceClient.detectExecutablePath())
        switcher = SwitcherController(hotKeyCenter: hotKeyCenter)
        expose = ExposeController(client: client, hotKeyCenter: hotKeyCenter)
        // The swipe HUD reuses the switcher's workspace snapshots as its
        // thumbnail previews.
        swipe = SwipeController(client: client) { [switcher] workspace in
            switcher.snapshotImage(for: workspace)
        }
        // So does the exposé's drag-to-workspace drop bar.
        expose.workspacePreview = switcher.workspacePreview
    }

    func start() {
        hotKeyCenter.onPressed = { [weak self] role in
            self?.dispatch(role)
        }

        switcher.onOpenSettings = { [weak self] in
            self?.showSettings()
        }

        statusBar.onShowOverview = { [weak self] in self?.expose.toggle() }
        statusBar.onShowAppWindows = { [weak self] in self?.expose.toggleAppWindows() }
        statusBar.onRefreshSnapshots = { [weak self] in self?.switcher.refreshSnapshotsFromMenu() }
        statusBar.onOpenSettings = { [weak self] in self?.showSettings() }
        statusBar.onQuit = { NSApp.terminate(nil) }
        statusBar.start()

        switcher.start()
        expose.start()
        swipe.start()

        swipeMonitor.onSwipeEvent = { [weak self] event in
            switch event.axis {
            case .horizontal:
                self?.swipe.handle(event)
            case .vertical:
                // Exposé toggles are discrete; only the release outcome
                // matters and a cancelled gesture does nothing.
                if case let .ended(_, steps) = event, steps != 0 {
                    self?.expose.handleSwipe(steps > 0 ? .up : .down)
                }
            }
        }
        expose.onSwipePreferenceChanged = { [weak self] in self?.updateSwipeMonitor() }
        swipe.onSwipePreferenceChanged = { [weak self] in self?.updateSwipeMonitor() }
        updateSwipeMonitor()
    }

    /// The monitor runs while any feature wants trackpad swipes and stops
    /// when none does, so the private framework is only touched when needed.
    private func updateSwipeMonitor() {
        let wanted = expose.wantsSwipeGestures || swipe.wantsSwipeGestures
        // Setting this restarts a running monitor when the value changed.
        swipeMonitor.stepDistanceMM = Float(swipe.stepDistanceMM)
        var running = false
        if wanted {
            running = swipeMonitor.start()
            if !running {
                fputs("AeroKit: trackpad swipe monitor failed to start\n", stderr)
            }
        } else {
            swipeMonitor.stop()
        }
        expose.updateSwipeAvailability(monitorRunning: running || !wanted)
        swipe.updateSwipeAvailability(monitorRunning: running || !wanted)
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                switcherPane: switcher.makeSettingsPane(),
                exposePane: expose.makeSettingsPane(),
                swipePane: swipe.makeSettingsPane()
            ) { [weak self] in
                self?.switcher.refreshSettingsStatus()
            }
        }
        // AeroSpace parks windows of non-focused workspaces off-screen, so
        // reopening settings from another workspace would show nothing
        // without a summon. The user's workspace must be read BEFORE the
        // window becomes key: that alone flips AeroSpace's focused workspace
        // to wherever the window currently lives — which is also why
        // overlapping invocations must not interleave.
        guard settingsSummonTask == nil else { return }
        let client = client
        settingsSummonTask = Task { [weak self] in
            let workspace = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    return try client.focusedWorkspaceName()
                } catch {
                    fputs("AeroKit: reading focused workspace failed: \(error)\n", stderr)
                    return nil
                }
            }.value

            guard let self else { return }
            settingsWindow?.show()

            if let workspace, let windowID = settingsWindow?.windowID {
                await Task.detached(priority: .userInitiated) {
                    do {
                        try client.summonWindow(id: windowID, toWorkspace: workspace)
                    } catch {
                        fputs("AeroKit: summoning settings window failed: \(error)\n", stderr)
                    }
                }.value
            }
            settingsSummonTask = nil
        }
    }

    func toggleExpose() {
        expose.toggle()
    }

    func toggleAppExpose() {
        expose.toggleAppWindows()
    }

    private func dispatch(_ role: HotKeyRole) {
        switch role {
        case .cycleForward, .cycleBackward, .escape:
            switcher.handle(role)
        case .exposeToggle:
            expose.toggle()
        case .exposeAppToggle:
            expose.toggleAppWindows()
        }
    }
}
