import AeroKitCore
import AppKit
import ExposeFeature
import Foundation
import SwitcherFeature

/// Owns the pieces every feature shares — the Carbon hotkey center, the
/// status bar item, and the settings window — and routes events to the
/// switcher and exposé controllers.
@MainActor
final class AppCoordinator {
    private let hotKeyCenter = HotKeyCenter()
    private let statusBar = StatusBarController()
    private let client: AeroSpaceClient
    private let switcher: SwitcherController
    private let expose: ExposeController
    private var settingsWindow: SettingsWindowController?
    private var settingsSummonTask: Task<Void, Never>?

    init() {
        PreferencesMigration.migrateIfNeeded()

        client = AeroSpaceClient(executablePath: AeroSpaceClient.detectExecutablePath())
        switcher = SwitcherController(hotKeyCenter: hotKeyCenter)
        expose = ExposeController(client: client, hotKeyCenter: hotKeyCenter)
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
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                switcherPane: switcher.makeSettingsPane(),
                exposePane: expose.makeSettingsPane()
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
