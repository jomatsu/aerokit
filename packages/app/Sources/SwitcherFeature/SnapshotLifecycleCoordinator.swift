import AeroKitCore
import Combine
import Foundation

@MainActor
final class SnapshotLifecycleCoordinator {
    var onStarted: (() -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?
    var onWorkspaceChangeRequest: (() -> Void)?
    var onInvalidatePresentation: (() -> Void)?
    var onLogError: ((String) -> Void)?
    var onPurgeCompleted: ((String?) -> Void)?

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
    private var deletionRequested = false

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
                do { try await then(.success(BlockingWork.run(work))) } catch { then(.failure(error)) }
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

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        preferences.$autoRefresh.dropFirst()
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in self?.scheduler.cancelPending() }
            .store(in: &cancellables)
    }

    /// Wait for the writer before removing its output; no refresh can start until deletion finishes.
    func deleteSnapshots() {
        guard !deletionRequested else { return }
        deletionRequested = true
        preferences.autoRefresh = false
        scheduler.suspend()
        if !scheduler.isRefreshing {
            purgeSnapshots()
        }
    }

    private func bindScheduler() {
        scheduler.onRefreshStarted = { [weak self] in self?.onStarted?() }
        scheduler.onRefreshProgress = { [weak self] completed, total in self?.onProgress?(completed, total) }
        scheduler.onRefreshFinished = { [weak self] _, _ in
            self?.onFinished?()
            if self?.deletionRequested == true {
                self?.purgeSnapshots()
            }
        }
        scheduler.onRefreshFailed = { [weak self] message in
            self?.onFailed?(message)
            if self?.deletionRequested == true {
                self?.purgeSnapshots()
            }
        }
        scheduler.onRequestReceived = { [weak self] reason in
            if reason == .workspaceChange {
                self?.onWorkspaceChangeRequest?()
            }
        }
    }

    private func purgeSnapshots() {
        onInvalidatePresentation?()
        let rootPath = configuration.snapshotRootPath
        let removeItem = removeItem
        runWork({
            do { try removeItem(rootPath) } catch let error as CocoaError where error.code == .fileNoSuchFile {}
        }, { [weak self] result in
            guard let self else { return }
            deletionRequested = false
            scheduler.resume()
            var message: String?
            if case let .failure(error) = result {
                message = L10n.tr("Could not delete saved previews. \(error.localizedDescription)")
                onLogError?(message ?? "Could not delete saved previews.")
            }
            onPurgeCompleted?(message)
        })
    }
}
