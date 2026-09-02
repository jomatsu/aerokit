import AeroKitCore
import AppKit
import ExposeFeature
import Foundation
import SwipeFeature
import SwitcherFeature

private let log = AppLog(category: "app")

/// Owns the pieces every feature shares — the Carbon hotkey center, the
/// status bar item, the trackpad monitor, and the settings window — and
/// routes events to the switcher, exposé, and swipe controllers.
@MainActor
final class AppCoordinator {
    private let hotKeyCenter = HotKeyCenter()
    private let statusBar = StatusBarController()
    private let client: AeroSpaceClient
    /// One store, two settings panes: the switcher grid and the swipe ring
    /// share the workspace order.
    private let workspaceOrder = WorkspaceOrderStore()
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
        // Converts the LaunchAgent earlier releases wrote into an
        // SMAppService login item; idempotent and cheap after the first run.
        LaunchAtLogin.migrateIfNeeded()

        client = AeroSpaceClient(executablePath: AeroSpaceClient.detectExecutablePath())
        switcher = SwitcherController(hotKeyCenter: hotKeyCenter, workspaceOrder: workspaceOrder)
        expose = ExposeController(client: client, hotKeyCenter: hotKeyCenter)
        // The swipe HUD and the exposé's drag-to-workspace drop bar both
        // reuse the switcher's workspace snapshots as thumbnail previews;
        // the Sendable lookup lets each feature decode them off the main
        // actor.
        swipe = SwipeController(
            client: client,
            workspaceOrder: workspaceOrder,
            workspacePreview: switcher.workspacePreview
        )
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
        showOnboardingIfNeeded()
    }

    /// First-run affordance: a feature missing a permission (Screen
    /// Recording, Accessibility) or a failed hotkey registration is
    /// explained inline in its settings pane, so surface the settings
    /// window when any feature raises its flag. Checked after the features
    /// started — that's when hotkeys registered and the flags are accurate.
    private func showOnboardingIfNeeded() {
        guard switcher.needsOnboarding || expose.needsOnboarding else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showSettings()
        }
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
                log.error("trackpad swipe monitor failed to start")
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
                client: client,
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
            let workspace = await BlockingWork.run { () -> String? in
                do {
                    return try client.focusedWorkspaceName()
                } catch {
                    log.error("reading focused workspace failed: \(error)")
                    return nil
                }
            }

            guard let self else { return }
            settingsWindow?.show()

            if let workspace, let windowID = settingsWindow?.windowID {
                await BlockingWork.run {
                    do {
                        try client.summonWindow(id: windowID, toWorkspace: workspace)
                    } catch {
                        log.error("summoning settings window failed: \(error)")
                    }
                }
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

    /// A workspace change from outside AeroKit — the exec-on-workspace-change
    /// hook reports the user's own AeroSpace keybindings, CLI switches, and
    /// other automation. Swipe decides whether the strip flashes.
    func showWorkspaceChangeHUD(workspace: String?, previous: String?) {
        log.notice("workspace changed outside AeroKit: \(previous ?? "?") → \(workspace ?? "?")")
        swipe.showWorkspaceChangeHUD()
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
