import AeroKitCore
import AppKit
import ExposeFeature
import Foundation
import SwiftUI
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
    /// The switcher grid and swipe ring share the order edited in Display.
    private let workspaceOrder = WorkspaceOrderStore()
    private let switcher: SwitcherController
    private let expose: ExposeController
    private let windowSwitcher: WindowSwitcherController
    private let swipe: SwipeController
    /// Shared because only one monitor can observe the trackpad: vertical
    /// swipes go to exposé, horizontal ones to the workspace switcher.
    private let swipeMonitor = TrackpadSwipeMonitor()
    private var settingsWindow: SettingsWindowController?
    private var settingsSummonTask: Task<Void, Never>?
    /// A fresh install gets the welcome tour once; upgrades never do.
    private let showsWelcome: Bool

    init() {
        showsWelcome = Self.claimWelcome()
        PreferencesMigration.migrateIfNeeded()
        // Converts the LaunchAgent earlier releases wrote into an
        // SMAppService login item; idempotent and cheap after the first run.
        LaunchAtLogin.migrateIfNeeded()

        client = AeroSpaceClient(executablePath: AeroSpaceClient.detectExecutablePath())
        switcher = SwitcherController(hotKeyCenter: hotKeyCenter, workspaceOrder: workspaceOrder)
        let exposePreferences = ExposePreferences()
        // The window switcher shares the exposé's pipeline and preference
        // store; one preferences instance keeps their hotkeys coherent.
        expose = ExposeController(client: client, hotKeyCenter: hotKeyCenter, preferences: exposePreferences)
        windowSwitcher = WindowSwitcherController(
            client: client,
            hotKeyCenter: hotKeyCenter,
            preferences: exposePreferences
        )
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
        statusBar.onQuit = { AppTermination.terminate() }
        statusBar.start()

        switcher.start()
        expose.start()
        windowSwitcher.start()
        swipe.start()

        swipeMonitor.onSwipeEvent = { [weak self] event in
            // A swipe takes the screen from the window switcher's strip.
            self?.windowSwitcher.cancelIfActive()
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
        // Swipes switch workspaces outside the switcher's own pipeline;
        // route the commit to the snapshot refresh those commits trigger,
        // so swipe-landed previews don't go stale.
        swipe.onWorkspaceSwitched = { [weak self] in
            self?.switcher.scheduleSnapshotRefreshForWorkspaceChange()
        }
        updateSwipeMonitor()
        showOnboardingIfNeeded()
    }

    /// Every AeroKit release has written the migration marker on its first
    /// run, so its absence means nothing ran here before. Read before the
    /// migration writes it; an upgrade is marked as having seen the tour.
    private static func claimWelcome(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: WelcomePresentation.shownKey) else { return false }
        guard defaults.object(forKey: PreferencesMigration.markerKey) == nil else {
            defaults.set(true, forKey: WelcomePresentation.shownKey)
            return false
        }
        return true
    }

    /// First-run affordance: missing Screen Recording permission or a
    /// failed hotkey registration is
    /// explained inline in its settings pane, so surface the settings
    /// window when any feature raises its flag. Checked after the features
    /// started — that's when hotkeys registered and the flags are accurate.
    private func showOnboardingIfNeeded() {
        guard showsWelcome || switcher.needsOnboarding || expose.needsOnboarding
            || windowSwitcher.needsOnboarding
        else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            showSettings()
            if showsWelcome {
                settingsWindow?.presentWelcome()
            }
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
                workspacesPane: makeWorkspacesSettingsPage(),
                windowsPane: makeWindowsSettingsPage(),
                previewPane: switcher.makePreviewSettingsPane(),
                welcomeFeatures: makeWelcomeFeatures()
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

    /// The welcome tour's pages: the everyday features, with the same demos
    /// as the settings (i) buttons. Experimental ones stay out of the tour.
    private func makeWelcomeFeatures() -> [WelcomeFeature] {
        [
            WelcomeFeature(
                title: "See all your workspaces",
                detail: """
                Like Mission Control, it shows what’s in every workspace side by side. Open it with \
                a shortcut and choose where to go.
                """,
                demo: AnyView(switcher.makeDemo())
            ),
            WelcomeFeature(
                title: "Swipe between workspaces",
                detail: """
                Just like switching desktops on a Mac, swipe left or right with three fingers to \
                move to the next workspace.
                """,
                demo: AnyView(swipe.makeDemo())
            ),
            WelcomeFeature(
                title: "See all windows in a workspace",
                detail: """
                Like App Exposé, it lays out the workspace’s windows so none overlap, including \
                ones hidden in an accordion layout. Press a number to switch.
                """,
                demo: AnyView(expose.makeOverviewDemo())
            ),
            WelcomeFeature(
                title: "Open the lists with a swipe",
                detail: """
                As on a Mac, swipe up with three fingers for the workspace’s windows, or down for \
                the current app’s windows.
                """,
                demo: AnyView(expose.makeGestureDemo())
            )
        ]
    }

    /// Everything that moves between workspaces — the grid, swipes, the
    /// name strip — plus the order they all share, edited in one place.
    private func makeWorkspacesSettingsPage() -> some View {
        SettingsPage(
            destination: .workspaces,
            subtitle: "Switch workspaces from the keyboard or with three-finger swipes.",
            resetMessage: """
            Restore the switcher, swipe, name strip, and workspace order. Preview images, macOS gestures, \
            and your AeroSpace configuration are kept.
            """,
            onReset: { [weak self] in
                self?.switcher.resetSettings()
                self?.swipe.resetSettings()
            },
            content: {
                switcher.makeSettingsSection()
                swipe.makeSettingsSection()
                swipe.makeNameStripSettingsSection()
                switcher.makeOrderSettingsSection()
            }
        )
    }

    /// Everything that finds or switches windows: the overview with its
    /// shortcuts and vertical gestures, and the experimental quick switcher.
    private func makeWindowsSettingsPage() -> some View {
        SettingsPage(
            destination: .windows,
            subtitle: "Find and switch windows with shortcuts or three-finger swipes.",
            resetMessage: """
            Restore the window overview, its gestures, and quick window switching. macOS gestures are kept.
            """,
            onReset: { [weak self] in self?.expose.resetSettings() },
            content: {
                expose.makeOverviewSettingsSection()
                expose.makeGestureSettingsSection()
                windowSwitcher.makeSettingsSection()
            }
        )
    }

    func toggleExpose() {
        expose.toggle()
    }

    func toggleAppExpose() {
        expose.toggleAppWindows()
    }

    /// An external workspace change (the exec-on-workspace-change hook's
    /// report): cancels the window switcher's now-stale strip and flashes
    /// the swipe HUD for the switch that just landed.
    func showWorkspaceChangeHUD(workspace: String?, previous: String?) {
        log.notice("workspace changed outside AeroKit: \(previous ?? "?") → \(workspace ?? "?")")
        windowSwitcher.cancelIfActive()
        // The hook is also the freshest signal that keyboard-driven switches
        // landed — refresh thumbnails the same way swipe commits do.
        switcher.scheduleSnapshotRefreshForWorkspaceChange()
        swipe.showWorkspaceChangeHUD()
    }

    private func dispatch(_ role: HotKeyRole) {
        // The window switcher's strip defers to whichever overlay owns the
        // screen first — they fight over the same key events.
        if role != .windowCycleForward, role != .windowCycleBackward {
            windowSwitcher.cancelIfActive()
        }
        switch role {
        case .cycleForward, .cycleBackward, .escape:
            switcher.handle(role)
        case .exposeToggle:
            expose.toggle()
        case .exposeAppToggle:
            expose.toggleAppWindows()
        case .windowCycleForward, .windowCycleBackward:
            // The strip defers to whichever overlay owns the screen first;
            // the two fight over the same key events.
            guard !expose.isActive, !switcher.isActive else {
                break
            }
            windowSwitcher.handle(role)
        }
    }
}
