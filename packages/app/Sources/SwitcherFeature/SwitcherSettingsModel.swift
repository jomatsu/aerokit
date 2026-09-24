import AeroKitCore
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
    @Published private(set) var hotKeyErrorMessage: LocalizedStringResource?

    let preferences: AppPreferences
    let workspaceOrder: WorkspaceOrderStore
    let loadWorkspaces: @Sendable () throws -> [WorkspaceOrderEntry]

    var onShowSwitcher: (() -> Void)?
    var onDeleteSnapshots: (() -> Void)?
    @Published private(set) var isDeletingSnapshots = false
    @Published private(set) var deleteError: String?

    var onRefreshSnapshots: (() -> Bool)?
    var onHotKeyRecordingChanged: ((Bool) -> Void)?

    private let configuration: SwitcherConfiguration
    private let snapshotStore: SnapshotStore

    init(
        configuration: SwitcherConfiguration,
        preferences: AppPreferences,
        workspaceOrder: WorkspaceOrderStore,
        loadWorkspaces: @escaping @Sendable () throws -> [WorkspaceOrderEntry],
        snapshotStore: SnapshotStore
    ) {
        self.configuration = configuration
        self.preferences = preferences
        self.workspaceOrder = workspaceOrder
        self.loadWorkspaces = loadWorkspaces
        self.snapshotStore = snapshotStore
    }

    func refreshStatus() {
        screenCaptureGranted = ScreenCapturePermission.isGranted

        guard let directory = snapshotStore.currentDirectory() else {
            snapshotModifiedAt = nil
            return
        }

        let manifest = directory.appendingPathComponent("manifest.tsv")
        snapshotModifiedAt = manifest.contentModificationDate ?? directory.contentModificationDate
    }

    func openSnapshotFolder() {
        let url: URL = if let current = snapshotStore.currentDirectory() {
            current
        } else {
            URL(fileURLWithPath: configuration.snapshotRootPath, isDirectory: true)
        }
        NSWorkspace.shared.open(url)
    }

    func setHotKeyRecording(_ isRecording: Bool) {
        onHotKeyRecordingChanged?(isRecording)
    }

    func markHotKeyRegistration(error message: LocalizedStringResource?) {
        hotKeyErrorMessage = message
    }

    func deleteSnapshots() {
        guard !isDeletingSnapshots else { return }
        isDeletingSnapshots = true
        deleteError = nil
        onDeleteSnapshots?()
    }

    func markSnapshotsDeleted(error: String?) {
        isDeletingSnapshots = false
        deleteError = error
        refreshStatus()
    }

    func refreshSnapshots() {
        guard !isDeletingSnapshots else { return }
        if onRefreshSnapshots?() != true {
            refreshStatus()
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
