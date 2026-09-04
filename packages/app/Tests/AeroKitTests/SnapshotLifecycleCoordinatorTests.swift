import XCTest
@testable import SwitcherFeature

@MainActor
final class SnapshotLifecycleCoordinatorTests: XCTestCase {
    private var fixture: SnapshotSchedulerFixture!
    private var events: [String] = []
    private var coordinator: SnapshotLifecycleCoordinator!

    override func setUp() async throws {
        fixture = try SnapshotSchedulerFixture()
        events = []
        coordinator = makeCoordinator()
        wireCoordinator()
    }

    override func tearDown() async throws {
        XCTAssertFalse(fixture?.refresh.hasPending ?? false, "started refresh was not resolved")
        fixture?.tearDown()
        fixture = nil
        coordinator = nil
    }

    func testObservationDoesNotPurgeUntilStarted() throws {
        try fixture.plantMarker()
        fixture.preferences.autoRefresh = false
        XCTAssertTrue(fixture.markerExists())
        XCTAssertEqual(events, [])
        coordinator.startObserving()
        XCTAssertEqual(events, [])
        XCTAssertTrue(fixture.markerExists())
    }

    func testTurningAutoRefreshOffCancelsPendingThenPurgesRoot() throws {
        try fixture.plantMarker()
        coordinator.startObserving()
        XCTAssertTrue(fixture.scheduler.schedule(reason: .workspaceChange))
        XCTAssertEqual(fixture.timers.count, 1)

        fixture.preferences.autoRefresh = false

        XCTAssertEqual(fixture.timers.count, 0)
        XCTAssertEqual(events, ["invalidate", "purged"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path))
        fixture.timers.fireNext()
        XCTAssertEqual(fixture.refresh.startedCount, 0)
    }

    func testOffTransitionCancelsTimersBeforeHeldPurgeCompletes() async throws {
        let purge = HeldPurgeWork()
        let held = expectation(description: "purge held")
        let completed = expectation(description: "purge completed")
        purge.onHold = { held.fulfill() }
        let runWork: (
            @escaping @Sendable () throws -> Void,
            @escaping @MainActor (Result<Void, any Error>) -> Void
        ) -> Void = { work, then in
            purge.run(work, then: then)
        }
        coordinator = makeCoordinator(runWork: runWork)
        wireCoordinator()
        coordinator.onPurgeCompleted = { [weak self] in
            self?.events.append("purged")
            completed.fulfill()
        }

        try fixture.plantMarker()
        coordinator.startObserving()
        XCTAssertTrue(fixture.scheduler.schedule(reason: .workspaceChange))
        fixture.preferences.autoRefresh = false

        await fulfillment(of: [held], timeout: 1)
        XCTAssertEqual(fixture.timers.count, 0)
        XCTAssertEqual(events, ["invalidate"])
        XCTAssertTrue(fixture.markerExists())

        purge.release()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(events, ["invalidate", "purged"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path))
    }

    func testInFlightAutomaticCompletionPurgesRecreatedRoot() async throws {
        try fixture.plantMarker()
        coordinator.startObserving()
        let started = fixture.expectRefreshStarted()
        XCTAssertTrue(fixture.scheduler.schedule(reason: .workspaceChange))
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)

        fixture.preferences.autoRefresh = false
        XCTAssertEqual(events, ["started", "invalidate", "purged"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path))

        try fixture.plantMarker()
        XCTAssertTrue(fixture.markerExists())

        let finished = expectation(description: "finished")
        let secondPurge = expectation(description: "second purge")
        coordinator.onFinished = { [weak self] in
            self?.events.append("finished")
            finished.fulfill()
        }
        coordinator.onPurgeCompleted = { [weak self] in
            self?.events.append("purged")
            secondPurge.fulfill()
        }
        fixture.refresh.succeed()
        await fulfillment(of: [finished, secondPurge], timeout: 1)
        XCTAssertEqual(events, ["started", "invalidate", "purged", "finished", "invalidate", "purged"])
        XCTAssertFalse(fixture.markerExists())
    }

    func testForcedManualRefreshWhileOffPreservesRoot() async throws {
        try fixture.plantMarker()
        fixture.preferences.autoRefresh = false
        coordinator.startObserving()
        let started = fixture.expectRefreshStarted()
        let finished = expectation(description: "finished")
        coordinator.onFinished = { [weak self] in
            self?.events.append("finished")
            finished.fulfill()
        }
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.refresh.succeed()
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(events, ["started", "finished"])
        XCTAssertTrue(fixture.markerExists())
    }

    func testMissingRootPurgeIsSuccessfulNoOp() {
        coordinator.startObserving()
        try? FileManager.default.removeItem(at: fixture.root)
        fixture.preferences.autoRefresh = false
        XCTAssertEqual(events, ["invalidate", "purged"])
        XCTAssertFalse(events.contains { $0.hasPrefix("log:") })
    }

    func testPurgeFailureIsLoggedThenStatusCallbackRuns() {
        let failingRemove: @Sendable (String) throws -> Void = { _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        coordinator = makeCoordinator(removeItem: failingRemove)
        wireCoordinator()
        coordinator.startObserving()
        fixture.preferences.autoRefresh = false
        XCTAssertEqual(events.first, "invalidate")
        XCTAssertEqual(events.last, "purged")
        XCTAssertTrue(events.contains { $0.hasPrefix("log:Failed to delete previews:") })
    }

    func testFinishedRunsBeforeCompletionPurge() async {
        coordinator.startObserving()
        let started = fixture.expectRefreshStarted()
        XCTAssertTrue(fixture.scheduler.schedule(reason: .windowDetected))
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.preferences.autoRefresh = false
        events.removeAll()

        let finished = expectation(description: "finished")
        let purged = expectation(description: "purged")
        coordinator.onFinished = { [weak self] in
            self?.events.append("finished")
            finished.fulfill()
        }
        coordinator.onPurgeCompleted = { [weak self] in
            self?.events.append("purged")
            purged.fulfill()
        }
        fixture.refresh.succeed()
        await fulfillment(of: [finished, purged], timeout: 1)
        XCTAssertEqual(events, ["finished", "invalidate", "purged"])
    }

    func testWorkspaceChangeRequestIsForwardedAndOtherReasonsAreNot() {
        fixture.scheduler.onRequestReceived?(.request)
        fixture.scheduler.onRequestReceived?(.windowDetected)
        fixture.scheduler.onRequestReceived?(.workspaceChange)
        XCTAssertEqual(events, ["hide"])
    }

    func testProgressIsForwarded() async {
        coordinator.startObserving()
        let started = fixture.expectRefreshStarted()
        let progressed = expectation(description: "progress")
        let finished = expectation(description: "finished")
        coordinator.onProgress = { [weak self] completed, total in
            self?.events.append("progress:\(completed)/\(total)")
            progressed.fulfill()
        }
        coordinator.onFinished = { [weak self] in
            self?.events.append("finished")
            finished.fulfill()
        }
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.refresh.emitProgress(completed: 2, total: 4)
        await fulfillment(of: [progressed], timeout: 1)
        fixture.refresh.succeed()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(events, ["started", "progress:2/4", "finished"])
    }

    func testRepeatedStartObservingDoesNotDuplicatePurge() throws {
        try fixture.plantMarker()
        coordinator.startObserving()
        coordinator.startObserving()
        fixture.preferences.autoRefresh = false
        XCTAssertEqual(events, ["invalidate", "purged"])
    }

    private func makeCoordinator(
        removeItem: @escaping @Sendable (String) throws -> Void = { try FileManager.default.removeItem(atPath: $0) },
        runWork: @escaping (
            @escaping @Sendable () throws -> Void,
            @escaping @MainActor (Result<Void, any Error>) -> Void
        ) -> Void = { work, then in
            do {
                try work()
                then(.success(()))
            } catch {
                then(.failure(error))
            }
        }
    ) -> SnapshotLifecycleCoordinator {
        SnapshotLifecycleCoordinator(
            configuration: fixture.configuration,
            preferences: fixture.preferences,
            scheduler: fixture.scheduler,
            removeItem: removeItem,
            runWork: runWork
        )
    }

    private func wireCoordinator() {
        coordinator.onStarted = { [weak self] in self?.events.append("started") }
        coordinator.onProgress = { [weak self] completed, total in
            self?.events.append("progress:\(completed)/\(total)")
        }
        coordinator.onFinished = { [weak self] in self?.events.append("finished") }
        coordinator.onFailed = { [weak self] message in self?.events.append("failed:\(message)") }
        coordinator.onWorkspaceChangeRequest = { [weak self] in self?.events.append("hide") }
        coordinator.onInvalidatePresentation = { [weak self] in self?.events.append("invalidate") }
        coordinator.onLogError = { [weak self] message in self?.events.append("log:\(message)") }
        coordinator.onPurgeCompleted = { [weak self] in self?.events.append("purged") }
    }
}

@MainActor
private final class HeldPurgeWork {
    var onHold: (() -> Void)?
    private var work: (@Sendable () throws -> Void)?
    private var then: (@MainActor (Result<Void, any Error>) -> Void)?

    func run(
        _ work: @escaping @Sendable () throws -> Void,
        then: @escaping @MainActor (Result<Void, any Error>) -> Void
    ) {
        self.work = work
        self.then = then
        onHold?()
    }

    func release() {
        guard let work, let then else {
            return
        }
        self.work = nil
        self.then = nil
        do {
            try work()
            then(.success(()))
        } catch {
            then(.failure(error))
        }
    }
}
