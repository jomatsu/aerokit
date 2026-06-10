import Darwin
import Foundation

@MainActor
public final class SnapshotRefreshScheduler {
    public var onRequestReceived: ((SnapshotReason) -> Void)?
    public var onRefreshFinished: ((URL?) -> Void)?
    public var onRefreshFailed: ((String) -> Void)?

    private let configuration: SwitcherConfiguration
    private let snapshotStore: SnapshotStore
    private let runner: any CommandRunning

    private var debounceTimer: Timer?
    private var requestWatcher: (any DispatchSourceFileSystemObject)?
    private var requestDirectoryFileDescriptor: CInt = -1
    private var pendingReason: SnapshotReason?
    private var queuedReason: SnapshotReason?
    private var isRunning = false
    private var lastStartedAt = Date.distantPast
    private var retryAfterFailureAt = Date.distantPast

    public init(
        configuration: SwitcherConfiguration,
        snapshotStore: SnapshotStore,
        runner: any CommandRunning = ProcessRunner()
    ) {
        self.configuration = configuration
        self.snapshotStore = snapshotStore
        self.runner = runner
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
        guard configuration.snapshotRefreshOnShow else {
            return false
        }
        guard snapshotStore.isStale(maxAge: configuration.snapshotStaleInterval) else {
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

    @discardableResult
    private func schedule(reason: SnapshotReason, force: Bool) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: configuration.snapshotScriptPath) else {
            return false
        }
        guard force || retryAfterFailureAt.timeIntervalSinceNow <= 0 else {
            return false
        }

        if isRunning {
            queuedReason = reason
            return true
        }

        pendingReason = reason
        debounceTimer?.invalidate()

        let delay: TimeInterval
        if force {
            delay = 0
        } else {
            let settleDelay = settleInterval(for: reason)
            let nextAllowed = lastStartedAt.addingTimeInterval(configuration.snapshotMinInterval)
            let minIntervalDelay = max(0, nextAllowed.timeIntervalSinceNow)
            delay = max(settleDelay, minIntervalDelay)
        }

        debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startRefresh()
            }
        }
        return true
    }

    private func startRefresh() {
        debounceTimer?.invalidate()
        debounceTimer = nil

        guard FileManager.default.isExecutableFile(atPath: configuration.snapshotScriptPath) else {
            return
        }
        guard ScreenCapturePermission.isGranted else {
            pendingReason = nil
            retryAfterFailureAt = Date().addingTimeInterval(configuration.snapshotFailureBackoff)
            onRefreshFailed?("Screen Recording permission is required for AeroSwitcher.app")
            return
        }

        let reason = pendingReason
        pendingReason = nil
        isRunning = true
        lastStartedAt = Date()

        DispatchQueue.global(qos: .utility).async { [configuration, runner] in
            let result: Result<URL?, any Error>
            do {
                let processResult = try runner.run(
                    configuration.snapshotScriptPath,
                    arguments: ["--configured", "--current"]
                )
                let outputDirectory = processResult.standardOutput
                    .split(whereSeparator: \.isNewline)
                    .last
                    .map(String.init)
                    .map { URL(fileURLWithPath: $0) }
                result = .success(outputDirectory)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                self.finishRefresh(result: result, triggeringReason: reason)
            }
        }
    }

    private func finishRefresh(result: Result<URL?, any Error>, triggeringReason: SnapshotReason?) {
        isRunning = false

        switch result {
        case let .success(directory):
            retryAfterFailureAt = Date.distantPast
            onRefreshFinished?(directory)
        case let .failure(error):
            retryAfterFailureAt = Date().addingTimeInterval(configuration.snapshotFailureBackoff)
            onRefreshFailed?("\(error)")
        }

        if let queuedReason {
            self.queuedReason = nil
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
