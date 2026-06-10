import AppKit
import Combine
import Foundation

@MainActor
final class SwitcherSettingsModel: ObservableObject {
    @Published private(set) var screenCaptureGranted = false
    @Published private(set) var snapshotDirectoryPath = "No snapshot directory found"
    @Published private(set) var snapshotModifiedText = "Unknown"
    @Published private(set) var isRefreshingSnapshots = false
    @Published private(set) var statusMessage = "Ready"

    var onRefreshSnapshots: (() -> Bool)?

    private let configuration: SwitcherConfiguration
    private let snapshotStore: SnapshotStore
    private let dateFormatter: DateFormatter

    init(configuration: SwitcherConfiguration, snapshotStore: SnapshotStore) {
        self.configuration = configuration
        self.snapshotStore = snapshotStore
        dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
    }

    func refreshStatus() {
        screenCaptureGranted = ScreenCapturePermission.isGranted

        guard let directory = snapshotStore.currentDirectory() else {
            snapshotDirectoryPath = configuration.snapshotRootPath
            snapshotModifiedText = "No valid snapshot yet"
            return
        }

        snapshotDirectoryPath = directory.path
        let manifest = directory.appendingPathComponent("manifest.tsv")
        if let modifiedAt = manifest.contentModificationDate ?? directory.contentModificationDate {
            snapshotModifiedText = dateFormatter.string(from: modifiedAt)
        } else {
            snapshotModifiedText = "Unknown"
        }
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        guard let url else {
            return
        }
        statusMessage = "Grant Screen Recording for AeroSwitcher.app in System Settings"
        NSWorkspace.shared.open(url)
    }

    func requestScreenCapturePermission() {
        if ScreenCapturePermission.request() {
            statusMessage = "Screen Recording permission granted"
        } else {
            statusMessage = "Use the macOS prompt to open Screen Recording settings"
        }
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

    func refreshSnapshots() {
        guard onRefreshSnapshots?() == true else {
            refreshStatus()
            return
        }
    }

    func markSnapshotRefreshStarted() {
        isRefreshingSnapshots = true
        statusMessage = "Refreshing snapshots..."
    }

    func markSnapshotRefreshFinished() {
        isRefreshingSnapshots = false
        statusMessage = "Snapshots refreshed"
        refreshStatus()
    }

    func markSnapshotRefreshFailed(_ message: String) {
        isRefreshingSnapshots = false
        statusMessage = message
        refreshStatus()
    }
}
