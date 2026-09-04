import XCTest
@testable import SwitcherFeature

@MainActor
final class SnapshotRefreshSchedulerTests: XCTestCase {
    private var fixture: SnapshotSchedulerFixture!

    override func setUp() async throws {
        fixture = try SnapshotSchedulerFixture()
    }

    override func tearDown() async throws {
        XCTAssertFalse(fixture?.refresh.hasPending ?? false, "started refresh was not resolved")
        fixture?.tearDown()
        fixture = nil
    }

    func testScheduleRejectedWhenAutoRefreshOffUnlessForced() {
        fixture.preferences.autoRefresh = false
        XCTAssertFalse(fixture.scheduler.schedule(reason: .workspaceChange))
        XCTAssertEqual(fixture.timers.count, 0)
        XCTAssertTrue(fixture.scheduler.refreshNow())
        XCTAssertEqual(fixture.timers.delays, [0])
    }

    func testPendingScheduleOverwritesArmedTimer() {
        XCTAssertTrue(fixture.scheduler.schedule(reason: .workspaceChange))
        XCTAssertEqual(fixture.timers.delays, [fixture.configuration.snapshotWorkspaceSettle])
        XCTAssertTrue(fixture.scheduler.schedule(reason: .windowDetected))
        XCTAssertEqual(fixture.timers.count, 1)
        XCTAssertEqual(fixture.timers.delays, [fixture.configuration.snapshotWindowSettle])
    }

    func testCancelPendingDropsArmedTimer() {
        XCTAssertTrue(fixture.scheduler.schedule(reason: .chooserShow))
        fixture.scheduler.cancelPending()
        XCTAssertEqual(fixture.timers.count, 0)
        fixture.timers.fireNext()
        XCTAssertEqual(fixture.refresh.startedCount, 0)
    }

    func testRefreshNowReportsProgressAndRequestReason() async {
        var finishedReason: SnapshotReason?
        let started = fixture.expectRefreshStarted()
        let progressed = fixture.expectProgress(completed: 1, total: 2)
        let finished = fixture.expectFinished { _, reason in
            finishedReason = reason
        }

        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.refresh.emitProgress(completed: 1, total: 2)
        await fulfillment(of: [progressed], timeout: 1)
        fixture.refresh.succeed()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(finishedReason, .request)
    }

    func testQueuedReasonIsOverwrittenWhileRunning() async {
        var finishedReasons: [SnapshotReason?] = []
        let started = fixture.expectRefreshStarted()
        let finished = fixture.expectFinished { _, reason in
            finishedReasons.append(reason)
        }

        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.clock.now += fixture.preferences.refreshFrequency.minInterval
        XCTAssertTrue(fixture.scheduler.schedule(reason: .workspaceChange))
        XCTAssertTrue(fixture.scheduler.schedule(reason: .windowDetected))
        fixture.refresh.succeed()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(finishedReasons, [.request])
        XCTAssertEqual(fixture.timers.delays, [fixture.configuration.snapshotWindowSettle])
    }

    func testQueuedRequestReschedulesWithoutForce() async {
        let started = fixture.expectRefreshStarted()
        let finished = fixture.expectFinished()

        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.clock.now += fixture.preferences.refreshFrequency.minInterval
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.refresh.succeed()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(fixture.timers.delays, [fixture.configuration.snapshotDebounce])
    }

    func testQueuedRequestIsDroppedWhenAutoRefreshIsOff() async {
        let started = fixture.expectRefreshStarted()
        let finished = fixture.expectFinished()

        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.preferences.autoRefresh = false
        fixture.refresh.succeed()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(fixture.timers.count, 0)
    }

    func testMinIntervalDelaysAutomaticSchedule() async {
        let started = fixture.expectRefreshStarted()
        let finished = fixture.expectFinished()
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.refresh.succeed()
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertTrue(fixture.scheduler.schedule(reason: .chooserShow))
        XCTAssertEqual(fixture.timers.delays, [fixture.preferences.refreshFrequency.minInterval])

        fixture.clock.now += fixture.preferences.refreshFrequency.minInterval
        fixture.scheduler.cancelPending()
        XCTAssertTrue(fixture.scheduler.schedule(reason: .chooserShow))
        XCTAssertEqual(fixture.timers.delays, [fixture.configuration.snapshotChooserSettle])
    }

    func testForcedRefreshIgnoresMinInterval() async {
        let started = fixture.expectRefreshStarted()
        let finished = fixture.expectFinished()
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.refresh.succeed()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(fixture.scheduler.refreshNow())
        XCTAssertEqual(fixture.timers.delays, [0])
    }

    func testPermissionFailureSetsBackoffAndExactMessage() async {
        var message: String?
        let failed = fixture.expectFailed { message = $0 }
        fixture.screenRecording.isGranted = false
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(message, "Screen Recording permission is required for AeroKit.app")
        XCTAssertEqual(fixture.refresh.startedCount, 0)
        XCTAssertFalse(fixture.scheduler.schedule(reason: .workspaceChange))
        XCTAssertTrue(fixture.scheduler.refreshNow())
        XCTAssertEqual(fixture.timers.delays, [0])
    }

    func testEngineFailureSetsBackoffUntilClockElapses() async {
        var message: String?
        let started = fixture.expectRefreshStarted()
        let failed = fixture.expectFailed { message = $0 }
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.refresh.fail(RefreshFailure())
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(message, "capture failed")
        XCTAssertFalse(fixture.scheduler.schedule(reason: .chooserShow))
        fixture.clock.now += fixture.configuration.snapshotFailureBackoff
        XCTAssertTrue(fixture.scheduler.schedule(reason: .chooserShow))
    }

    func testQueuedRequestAfterFailureIsRejectedByBackoff() async {
        let started = fixture.expectRefreshStarted()
        let failed = fixture.expectFailed()
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.refresh.fail(RefreshFailure())
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(fixture.timers.count, 0)
        XCTAssertFalse(fixture.scheduler.schedule(reason: .workspaceChange))
    }

    func testIdleForcedRefreshResetsFailureBackoff() async {
        let started = fixture.expectRefreshStarted()
        let failed = fixture.expectFailed()
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        fixture.refresh.fail(RefreshFailure())
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertFalse(fixture.scheduler.schedule(reason: .chooserShow))
        XCTAssertTrue(fixture.scheduler.refreshNow())
        XCTAssertEqual(fixture.timers.delays, [0])
    }

    func testRefreshOnShowIfNeededRequiresAutoRefreshAndStaleSnapshots() throws {
        try fixture.plantManifest(modified: Date())
        fixture.preferences.autoRefresh = false
        XCTAssertFalse(fixture.scheduler.refreshOnShowIfNeeded())
        fixture.preferences.autoRefresh = true
        XCTAssertFalse(fixture.scheduler.refreshOnShowIfNeeded())
        try fixture.plantManifest(modified: Date.distantPast)
        XCTAssertTrue(fixture.scheduler.refreshOnShowIfNeeded())
        XCTAssertEqual(fixture.timers.delays, [fixture.configuration.snapshotChooserSettle])
    }

    func testCancelPendingDropsQueuedFollowUp() async {
        let started = fixture.expectRefreshStarted()
        let finished = fixture.expectFinished()
        XCTAssertTrue(fixture.scheduler.refreshNow())
        fixture.timers.fireNext()
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(fixture.scheduler.schedule(reason: .windowDetected))
        fixture.scheduler.cancelPending()
        fixture.refresh.succeed()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(fixture.timers.count, 0)
    }
}
