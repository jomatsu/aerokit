import Foundation
import XCTest
@testable import SwitcherFeature

@MainActor
final class SnapshotSchedulerFixture {
    let clock = FakeClock()
    let timers = ManualTimerQueue()
    let refresh = ControllableRefresh()
    let screenRecording = ScreenRecordingGrant()
    let preferences: AppPreferences
    let store: SnapshotStore
    let scheduler: SnapshotRefreshScheduler
    let configuration: SwitcherConfiguration
    let root: URL
    private let suiteName: String

    init() throws {
        suiteName = "SnapshotSchedulerFixture-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        preferences = AppPreferences(defaults: defaults)

        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aerokit-scheduler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var configuration = SwitcherConfiguration()
        configuration.snapshotRootPath = root.path
        configuration.snapshotRequestDirectoryPath = root.appendingPathComponent("requests").path
        configuration.snapshotRequestFilePath = root.appendingPathComponent("requests/request.tsv").path
        self.configuration = configuration
        store = SnapshotStore(rootPath: root.path)

        let clock = clock
        let timers = timers
        let refresh = refresh
        let screenRecording = screenRecording
        scheduler = SnapshotRefreshScheduler(
            configuration: configuration,
            preferences: preferences,
            snapshotStore: store,
            now: { clock.now },
            scheduleTimer: { delay, fire in
                timers.schedule(delay: delay, work: fire)
            },
            invalidateTimer: { timers.invalidate($0) },
            isScreenRecordingGranted: { screenRecording.isGranted },
            performRefresh: { exclusions, onProgress in
                try await refresh.run(exclusions, onProgress: onProgress)
            }
        )
    }

    var markerURL: URL {
        root.appendingPathComponent("capture.jpg")
    }

    func tearDown() {
        refresh.resolveIfPending()
        scheduler.cancelPending()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    func expectRefreshStarted() -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "refresh started")
        refresh.onStarted = { expectation.fulfill() }
        return expectation
    }

    func expectFinished(
        _ handler: ((URL?, SnapshotReason?) -> Void)? = nil
    ) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "refresh finished")
        scheduler.onRefreshFinished = { url, reason in
            handler?(url, reason)
            expectation.fulfill()
        }
        return expectation
    }

    func expectFailed(_ handler: ((String) -> Void)? = nil) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "refresh failed")
        scheduler.onRefreshFailed = { message in
            handler?(message)
            expectation.fulfill()
        }
        return expectation
    }

    func expectProgress(
        completed: Int,
        total: Int
    ) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "refresh progress")
        scheduler.onRefreshProgress = { actualCompleted, actualTotal in
            XCTAssertEqual(actualCompleted, completed)
            XCTAssertEqual(actualTotal, total)
            expectation.fulfill()
        }
        return expectation
    }

    func plantMarker() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: markerURL)
    }

    func markerExists() -> Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    func plantManifest(modified: Date) throws {
        let current = root.appendingPathComponent("current", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        let manifest = current.appendingPathComponent("manifest.tsv")
        let header = [
            "timestamp", "workspace", "window_id", "app_id", "app_name", "window_title",
            "window_layout", "window_parent_container_layout", "workspace_root_container_layout",
            "file", "status"
        ].joined(separator: "\t")
        let row = [
            "2020-01-01T00:00:00+0000", "1", "1", "app", "App", "Title",
            "tiling", "h_tiles", "h_tiles", "/tmp/window.jpg", "captured"
        ].joined(separator: "\t")
        try "\(header)\n\(row)\n".write(to: manifest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: modified],
            ofItemAtPath: manifest.path
        )
    }
}

@MainActor
final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

@MainActor
final class ManualTimerQueue {
    private struct Item {
        let timer: Timer
        let delay: TimeInterval
        let work: @MainActor () -> Void
    }

    private var items: [Item] = []

    var delays: [TimeInterval] {
        items.map(\.delay)
    }

    var count: Int {
        items.count
    }

    func schedule(delay: TimeInterval, work: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in }
        items.append(Item(timer: timer, delay: delay, work: work))
        return timer
    }

    func invalidate(_ timer: Timer) {
        items.removeAll { $0.timer === timer }
        timer.invalidate()
    }

    func fireNext() {
        guard !items.isEmpty else {
            return
        }
        let item = items.removeFirst()
        item.work()
    }
}

@MainActor
final class ControllableRefresh {
    var onStarted: (() -> Void)?
    private var continuation: CheckedContinuation<URL, any Error>?
    private(set) var startedCount = 0
    private(set) var lastExclusions: Set<String> = []
    private var onProgress: (@Sendable (Int, Int) -> Void)?

    var hasPending: Bool {
        continuation != nil
    }

    func run(
        _ exclusions: Set<String>,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> URL {
        lastExclusions = exclusions
        self.onProgress = onProgress
        startedCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            onStarted?()
        }
    }

    func succeed(url: URL = URL(fileURLWithPath: "/tmp/current", isDirectory: true)) {
        resume(.success(url))
    }

    func fail(_ error: any Error) {
        resume(.failure(error))
    }

    func emitProgress(completed: Int, total: Int) {
        onProgress?(completed, total)
    }

    func resolveIfPending() {
        resume(.failure(RefreshFailure()))
    }

    private func resume(_ result: Result<URL, any Error>) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

@MainActor
final class ScreenRecordingGrant {
    var isGranted = true
}

struct RefreshFailure: Error, CustomStringConvertible {
    var description: String {
        "capture failed"
    }
}
