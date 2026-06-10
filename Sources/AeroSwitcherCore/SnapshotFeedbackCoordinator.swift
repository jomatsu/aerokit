import Foundation

/// Owns the transient refresh feedback shown in the overlay badge and the
/// settings window, including the auto-clear timers.
@MainActor
final class SnapshotFeedbackCoordinator {
    private(set) var isRefreshRunning = false
    private(set) var feedback: SnapshotRefreshFeedback = .idle

    /// Fired whenever feedback or running state changes.
    var onChange: (() -> Void)?
    /// Fired once when a refresh finishes successfully.
    var onRefreshCompleted: (() -> Void)?

    private let settingsModel: SwitcherSettingsModel
    private var clearWorkItem: DispatchWorkItem?

    init(settingsModel: SwitcherSettingsModel) {
        self.settingsModel = settingsModel
    }

    func markStarted() {
        clearWorkItem?.cancel()
        clearWorkItem = nil
        isRefreshRunning = true
        feedback = .refreshing(completed: 0, total: 0)
        settingsModel.markSnapshotRefreshStarted()
        onChange?()
    }

    func markProgress(completed: Int, total: Int) {
        guard isRefreshRunning else {
            return
        }
        feedback = .refreshing(completed: completed, total: total)
        settingsModel.markSnapshotRefreshProgress(completed: completed, total: total)
        onChange?()
    }

    func markFinished() {
        isRefreshRunning = false
        feedback = .success
        settingsModel.markSnapshotRefreshFinished()
        onRefreshCompleted?()
        onChange?()
        scheduleClear(after: 2.0)
    }

    func markFailed(_ message: String) {
        isRefreshRunning = false
        feedback = .failure(message)
        settingsModel.markSnapshotRefreshFailed(message)
        onChange?()
        scheduleClear(after: 4.0)
    }

    /// Failure feedback that doesn't belong to a snapshot refresh run,
    /// e.g. the workspace list could not be loaded.
    func showTransientFailure(_ message: String) {
        feedback = .failure(message)
        onChange?()
        scheduleClear(after: 4.0)
    }

    private func scheduleClear(after delay: TimeInterval) {
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !isRefreshRunning else {
                return
            }
            feedback = .idle
            onChange?()
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
