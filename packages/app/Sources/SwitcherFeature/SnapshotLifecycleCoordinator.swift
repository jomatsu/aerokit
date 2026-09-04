import AeroKitCore
import Combine
import Foundation

/// Owns auto-refresh OFF observation, scheduler callback routing, and
/// on-disk snapshot purge. Presentation, settings status, overlay updates,
/// prewarm, and feedback stay with the controller via callbacks.
@MainActor
final class SnapshotLifecycleCoordinator {
    var onStarted: (() -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    /// Completion feedback. Invoked before any post-run purge so a
    /// successful badge is not skipped when captures are about to be deleted.
    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?
    var onWorkspaceChangeRequest: (() -> Void)?
    var onInvalidatePresentation: (() -> Void)?
    var onLogError: ((String) -> Void)?
    var onPurgeCompleted: (() -> Void)?

    private let configuration: SwitcherConfiguration
    private let preferences: AppPreferences
    private let scheduler: SnapshotRefreshScheduler
    private let removeItem: @Sendable (String) throws -> Void
    private let runWork: (
        @escaping @Sendable () throws -> Void,
        @escaping @MainActor (Result<Void, any Error>) -> Void
    ) -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var isObserving = false

    init(
        configuration: SwitcherConfiguration,
        preferences: AppPreferences,
        scheduler: SnapshotRefreshScheduler,
        removeItem: @escaping @Sendable (String) throws -> Void = { try FileManager.default.removeItem(atPath: $0) },
        runWork: @escaping (
            @escaping @Sendable () throws -> Void,
            @escaping @MainActor (Result<Void, any Error>) -> Void
        ) -> Void = { work, then in
            Task {
                do {
                    try await then(.success(BlockingWork.run(work)))
                } catch {
                    then(.failure(error))
                }
            }
        }
    ) {
        self.configuration = configuration
        self.preferences = preferences
        self.scheduler = scheduler
        self.removeItem = removeItem
        self.runWork = runWork
        bindScheduler()
    }

    /// Starts auto-refresh OFF observation. Matches the controller's
    /// `start()` timing — constructing the coordinator must not purge.
    func startObserving() {
        guard !isObserving else {
            return
        }
        isObserving = true

        // Captured previews are recognizable window images plus a manifest
        // of window titles; they must not outlive the user's intent. Turning
        // auto-refresh off cancels queued captures and deletes the on-disk
        // tree — the refresh button recreates it on demand.
        preferences.$autoRefresh.dropFirst()
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.handleAutoRefreshDisabled()
            }
            .store(in: &cancellables)
    }

    private func bindScheduler() {
        scheduler.onRefreshStarted = { [weak self] in
            self?.onStarted?()
        }
        scheduler.onRefreshProgress = { [weak self] completed, total in
            self?.onProgress?(completed, total)
        }
        scheduler.onRefreshFinished = { [weak self] _, reason in
            self?.handleRefreshFinished(reason)
        }
        scheduler.onRefreshFailed = { [weak self] message in
            self?.onFailed?(message)
        }
        scheduler.onRequestReceived = { [weak self] reason in
            guard reason == .workspaceChange else {
                return
            }
            self?.onWorkspaceChangeRequest?()
        }
    }

    private func handleRefreshFinished(_ reason: SnapshotReason?) {
        onFinished?()
        // A background run in flight when auto-refresh was switched off
        // outlives the toggle's purge; its promoted captures must not
        // resurrect what the user just deleted. Explicit requests
        // (refresh button, menu) keep their result regardless.
        if !preferences.autoRefresh, reason != .request {
            purgeSnapshots()
        }
    }

    private func handleAutoRefreshDisabled() {
        scheduler.cancelPending()
        purgeSnapshots()
    }

    /// Removes every stored capture (images and the title manifest). The
    /// overlay and the swipe HUD fall back to placeholders on their next
    /// lookup; a manual refresh recreates the tree.
    private func purgeSnapshots() {
        onInvalidatePresentation?()
        let rootPath = configuration.snapshotRootPath
        let removeItem = removeItem
        runWork(
            {
                do {
                    try removeItem(rootPath)
                } catch let error as CocoaError where error.code == .fileNoSuchFile {
                    // Nothing captured yet — already the state the purge wants.
                }
            },
            { [weak self] result in
                guard let self else { return }
                if case let .failure(error) = result {
                    onLogError?("Failed to delete previews: \(error)")
                }
                onPurgeCompleted?()
            }
        )
    }
}
