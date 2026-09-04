import AeroKitCore
import Darwin
import Foundation

@MainActor
public final class SnapshotRefreshScheduler {
    public var onRequestReceived: ((SnapshotReason) -> Void)?
    public var onRefreshStarted: (() -> Void)?
    public var onRefreshProgress: ((Int, Int) -> Void)?
    /// Carries the reason that triggered the run so the consumer can tell a
    /// user-requested refresh from a background one — a background run that
    /// finishes after auto-refresh was turned off must not have its captures
    /// kept, while an explicit request keeps them regardless.
    public var onRefreshFinished: ((URL?, SnapshotReason?) -> Void)?
    public var onRefreshFailed: ((String) -> Void)?

    private let configuration: SwitcherConfiguration
    private let preferences: AppPreferences
    private let snapshotStore: SnapshotStore
    private let now: () -> Date
    private let scheduleTimer: (TimeInterval, @escaping @MainActor () -> Void) -> Timer
    private let invalidateTimer: (Timer) -> Void
    private let isScreenRecordingGranted: () -> Bool
    private let performRefresh: (Set<String>, @escaping @Sendable (Int, Int) -> Void) async throws -> URL

    private var debounceTimer: Timer?
    private var requestWatcher: (any DispatchSourceFileSystemObject)?
    private var requestDirectoryFileDescriptor: CInt = -1
    private var pendingReason: SnapshotReason?
    private var queuedReason: SnapshotReason?
    private var isRunning = false
    private var lastStartedAt = Date.distantPast
    private var retryAfterFailureAt = Date.distantPast

    public convenience init(
        configuration: SwitcherConfiguration,
        preferences: AppPreferences,
        snapshotStore: SnapshotStore,
        engine: SnapshotEngine
    ) {
        self.init(
            configuration: configuration,
            preferences: preferences,
            snapshotStore: snapshotStore,
            now: { Date() },
            scheduleTimer: { delay, fire in
                Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                    Task { @MainActor in
                        fire()
                    }
                }
            },
            invalidateTimer: { $0.invalidate() },
            isScreenRecordingGranted: { ScreenCapturePermission.isGranted },
            performRefresh: { exclusions, onProgress in
                try await engine.refresh(excluding: exclusions, onProgress: onProgress)
            }
        )
    }

    init(
        configuration: SwitcherConfiguration,
        preferences: AppPreferences,
        snapshotStore: SnapshotStore,
        now: @escaping () -> Date,
        scheduleTimer: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Timer,
        invalidateTimer: @escaping (Timer) -> Void,
        isScreenRecordingGranted: @escaping () -> Bool,
        performRefresh: @escaping (Set<String>, @escaping @Sendable (Int, Int) -> Void) async throws -> URL
    ) {
        self.configuration = configuration
        self.preferences = preferences
        self.snapshotStore = snapshotStore
        self.now = now
        self.scheduleTimer = scheduleTimer
        self.invalidateTimer = invalidateTimer
        self.isScreenRecordingGranted = isScreenRecordingGranted
        self.performRefresh = performRefresh
    }

    deinit {
        requestWatcher?.cancel()
        if requestDirectoryFileDescriptor >= 0 {
            close(requestDirectoryFileDescriptor)
        }
    }

    public func startWatchingRequests() {
        guard requestWatcher == nil else {
            return
        }

        try? FileManager.default.createDirectory(
            atPath: configuration.snapshotRequestDirectoryPath,
            withIntermediateDirectories: true
        )

        let descriptor = open(configuration.snapshotRequestDirectoryPath, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        requestDirectoryFileDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let reason = readRequestReason()
            onRequestReceived?(reason)
            schedule(reason: reason)
        }
        source.setCancelHandler { [weak self] in
            guard let self, requestDirectoryFileDescriptor >= 0 else { return }
            close(requestDirectoryFileDescriptor)
            requestDirectoryFileDescriptor = -1
        }
        source.resume()
        requestWatcher = source
    }

    @discardableResult
    public func refreshOnShowIfNeeded() -> Bool {
        guard preferences.autoRefresh else {
            return false
        }
        guard snapshotStore.isStale(maxAge: preferences.refreshFrequency.staleInterval) else {
            return false
        }
        return schedule(reason: .chooserShow)
    }

    @discardableResult
    public func schedule(reason: SnapshotReason) -> Bool {
        schedule(reason: reason, force: false)
    }

    @discardableResult
    public func refreshNow() -> Bool {
        retryAfterFailureAt = Date.distantPast
        return schedule(reason: .request, force: true)
    }

    /// Drops the debounce timer and any queued follow-up. Turning
    /// auto-refresh off must also cancel work already scheduled: `schedule`
    /// guards new requests, but an armed timer would still fire
    /// `startRefresh` and recapture right after the purge.
    public func cancelPending() {
        if let debounceTimer {
            invalidateTimer(debounceTimer)
        }
        debounceTimer = nil
        pendingReason = nil
        queuedReason = nil
    }

    @discardableResult
    private func schedule(reason: SnapshotReason, force: Bool) -> Bool {
        guard force || preferences.autoRefresh else {
            return false
        }
        guard force || retryAfterFailureAt.timeIntervalSince(now()) <= 0 else {
            return false
        }

        if isRunning {
            queuedReason = reason
            return true
        }

        pendingReason = reason
        if let debounceTimer {
            invalidateTimer(debounceTimer)
        }

        let delay: TimeInterval
        if force {
            delay = 0
        } else {
            let settleDelay = settleInterval(for: reason)
            let nextAllowed = lastStartedAt.addingTimeInterval(preferences.refreshFrequency.minInterval)
            let minIntervalDelay = max(0, nextAllowed.timeIntervalSince(now()))
            delay = max(settleDelay, minIntervalDelay)
        }

        debounceTimer = scheduleTimer(delay) { [weak self] in
            self?.startRefresh()
        }
        return true
    }

    private func startRefresh() {
        if let debounceTimer {
            invalidateTimer(debounceTimer)
        }
        debounceTimer = nil

        guard isScreenRecordingGranted() else {
            pendingReason = nil
            retryAfterFailureAt = now().addingTimeInterval(configuration.snapshotFailureBackoff)
            onRefreshFailed?("Screen Recording permission is required for AeroKit.app")
            return
        }

        let reason = pendingReason
        pendingReason = nil
        isRunning = true
        lastStartedAt = now()
        onRefreshStarted?()

        let exclusions = preferences.snapshotExclusions
        Task { @MainActor in
            let result: Result<URL?, any Error>
            do {
                result = try await .success(performRefresh(exclusions) { completed, total in
                    Task { @MainActor [weak self] in
                        self?.onRefreshProgress?(completed, total)
                    }
                })
            } catch {
                result = .failure(error)
            }
            finishRefresh(result: result, triggeringReason: reason)
        }
    }

    private func finishRefresh(result: Result<URL?, any Error>, triggeringReason: SnapshotReason?) {
        isRunning = false

        switch result {
        case let .success(directory):
            retryAfterFailureAt = Date.distantPast
            onRefreshFinished?(directory, triggeringReason)
        case let .failure(error):
            retryAfterFailureAt = now().addingTimeInterval(configuration.snapshotFailureBackoff)
            onRefreshFailed?("\(error)")
        }

        if let queuedReason {
            self.queuedReason = nil
            // Follow-up is never forced: a `.request` queued while a run was
            // already in flight goes through the autoRefresh / backoff /
            // settle path, not `refreshNow`.
            schedule(reason: queuedReason)
        }
    }

    private func settleInterval(for reason: SnapshotReason) -> TimeInterval {
        switch reason {
        case .chooserShow:
            configuration.snapshotChooserSettle
        case .workspaceChange:
            configuration.snapshotWorkspaceSettle
        case .windowDetected:
            configuration.snapshotWindowSettle
        case .request:
            configuration.snapshotDebounce
        }
    }

    private func readRequestReason() -> SnapshotReason {
        guard let line = try? String(contentsOfFile: configuration.snapshotRequestFilePath, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .first
        else {
            return .request
        }

        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count > 1 else {
            return .request
        }

        return SnapshotReason(rawValue: fields[1]) ?? .request
    }
}
