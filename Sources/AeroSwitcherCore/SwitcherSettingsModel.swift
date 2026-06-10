import AppKit
import Combine
import Foundation

@MainActor
final class SwitcherSettingsModel: ObservableObject {
    @Published private(set) var screenCaptureGranted = false
    @Published private(set) var snapshotModifiedAt: Date?
    @Published private(set) var isRefreshingSnapshots = false
    @Published private(set) var refreshProgress: (completed: Int, total: Int)?
    @Published private(set) var lastErrorMessage: String?

    @Published var launchAtLogin: Bool {
        didSet {
            // Comparing against the actual agent state both prevents redundant
            // launchctl calls and makes status-sync assignments no-ops.
            guard launchAtLogin != LaunchAtLogin.isEnabled else {
                return
            }
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }

    let preferences: AppPreferences
    let launchAtLoginAvailable = LaunchAtLogin.isAvailable

    var onRefreshSnapshots: (() -> Bool)?
    var onHotKeyRecordingChanged: ((Bool) -> Void)?

    /// Screen Recording grants only take effect after a relaunch, so remember
    /// the state the process started with to know when a relaunch is pending.
    private let grantedAtLaunch: Bool

    private let configuration: SwitcherConfiguration
    private let snapshotStore: SnapshotStore

    var needsRelaunch: Bool {
        screenCaptureGranted && !grantedAtLaunch
    }

    init(
        configuration: SwitcherConfiguration,
        preferences: AppPreferences,
        snapshotStore: SnapshotStore
    ) {
        self.configuration = configuration
        self.preferences = preferences
        self.snapshotStore = snapshotStore
        grantedAtLaunch = ScreenCapturePermission.isGranted
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func refreshStatus() {
        screenCaptureGranted = ScreenCapturePermission.isGranted
        launchAtLogin = LaunchAtLogin.isEnabled

        guard let directory = snapshotStore.currentDirectory() else {
            snapshotModifiedAt = nil
            return
        }

        let manifest = directory.appendingPathComponent("manifest.tsv")
        snapshotModifiedAt = manifest.contentModificationDate ?? directory.contentModificationDate
    }

    func requestScreenCapturePermission() {
        _ = ScreenCapturePermission.request()
        refreshStatus()
    }

    func openSnapshotFolder() {
        let url: URL = if let current = snapshotStore.currentDirectory() {
            current
        } else {
            URL(fileURLWithPath: configuration.snapshotRootPath, isDirectory: true)
        }
        NSWorkspace.shared.open(url)
    }

    func restartApplication() {
        ApplicationRelauncher.relaunch()
    }

    func setHotKeyRecording(_ isRecording: Bool) {
        onHotKeyRecordingChanged?(isRecording)
    }

    func refreshSnapshots() {
        guard onRefreshSnapshots?() == true else {
            refreshStatus()
            return
        }
    }

    func markSnapshotRefreshStarted() {
        isRefreshingSnapshots = true
        refreshProgress = nil
        lastErrorMessage = nil
    }

    func markSnapshotRefreshProgress(completed: Int, total: Int) {
        guard isRefreshingSnapshots, total > 0 else {
            return
        }
        refreshProgress = (completed: completed, total: total)
    }

    func markSnapshotRefreshFinished() {
        isRefreshingSnapshots = false
        refreshProgress = nil
        lastErrorMessage = nil
        refreshStatus()
    }

    func markSnapshotRefreshFailed(_ message: String) {
        isRefreshingSnapshots = false
        refreshProgress = nil
        lastErrorMessage = message
        refreshStatus()
    }
}
