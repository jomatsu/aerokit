import AppKit
import XCTest
@testable import AeroKitCore
@testable import SwipeFeature

@MainActor
final class SwipeControllerLifecycleTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var loader: FakeSwipeWorkspaceLoader!
    private var runner: ControllableCommandRunner!
    private var hud: RecordingHUD!
    private var clock: TestClock!
    private var preferences: SwipePreferences!
    private var orderStore: WorkspaceOrderStore!
    private var controller: SwipeController!
    private var switchedCount = 0

    override func setUp() async throws {
        suiteName = "SwipeControllerLifecycleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        loader = FakeSwipeWorkspaceLoader()
        runner = ControllableCommandRunner()
        hud = RecordingHUD()
        clock = TestClock()
        preferences = SwipePreferences(defaults: defaults)
        orderStore = WorkspaceOrderStore(defaults: defaults)
        orderStore.order = ["1", "2", "3"]
        switchedCount = 0
        controller = makeController()
    }

    override func tearDown() async throws {
        loader.cancelPendingRings()
        runner.releaseSwitch()
        defaults.removePersistentDomain(forName: suiteName)
        controller = nil
    }

    func testNextRingLoadWaitsForPriorCommit() async {
        runner.holdNextSwitch()
        controller.handle(.began(.horizontal))
        await loader.waitUntilRingLoadCount(1)
        loader.completeOldestRing(Self.defaultRing)
        // Fingers moving left; natural direction maps that onto the next workspace.
        controller.handle(.ended(.horizontal, steps: -1))
        await waitUntil { self.runner.switchTargets.count == 1 }

        controller.handle(.began(.horizontal))
        await yieldMainActor()
        XCTAssertEqual(loader.ringLoadCount, 1)

        runner.releaseSwitch()
        await loader.waitUntilRingLoadCount(2)
        XCTAssertEqual(runner.switchTargets, ["3"])
    }

    func testCancelledGestureDoesNotSwitch() async {
        loader.immediateRing = Self.defaultRing
        controller.handle(.began(.horizontal))
        controller.handle(.ended(.horizontal, steps: 0))
        await waitUntil { self.hud.settleCount == 1 }

        XCTAssertTrue(runner.switchTargets.isEmpty)
        XCTAssertEqual(switchedCount, 0)
    }

    func testNonWrappingEdgeDoesNotSwitch() async {
        preferences.wrapAround = false
        loader.immediateRing = loadedRing(current: "1")
        controller.handle(.began(.horizontal))
        // Natural direction: fingers moving right try to go past the first card.
        controller.handle(.ended(.horizontal, steps: 1))
        await waitUntil { self.hud.settleCount == 1 }

        XCTAssertTrue(runner.switchTargets.isEmpty)
        XCTAssertEqual(switchedCount, 0)
        XCTAssertEqual(hud.wrapAroundOnSettle, Optional(false))
    }

    func testWrapAroundSwitchesAtEdge() async {
        loader.immediateRing = loadedRing(current: "3")
        controller.handle(.began(.horizontal))
        controller.handle(.ended(.horizontal, steps: -1))
        await waitUntil { self.switchedCount == 1 }

        XCTAssertEqual(runner.switchTargets, ["1"])
    }

    func testNaturalDirectionMapsFingerLeftToNextWorkspace() async {
        loader.immediateRing = Self.defaultRing
        controller.handle(.began(.horizontal))
        await loader.waitUntilRingLoadCount(1)
        await waitUntil { self.hud.beganInteractively }
        controller.handle(.moved(.horizontal, progress: -1))
        controller.handle(.ended(.horizontal, steps: -1))
        await waitUntil { self.runner.switchTargets.count == 1 }

        XCTAssertEqual(hud.offsets, [0, 1])
        XCTAssertEqual(runner.switchTargets, ["3"])
    }

    func testStaleExternalFlashDoesNotReplaceNewerGesture() async {
        let flashPreview = NSImage(size: NSSize(width: 1, height: 1))
        controller.showWorkspaceChangeHUD()
        await loader.waitUntilRingLoadCount(1)

        controller.handle(.began(.horizontal))
        await loader.waitUntilRingLoadCount(2)

        loader.completeOldestRing(
            loadedRing(workspaces: ["flash"], current: "flash", previews: ["flash": flashPreview])
        )
        await yieldMainActor()
        XCTAssertEqual(hud.settleCount, 0)
        XCTAssertFalse(hud.beganInteractively)

        loader.completeOldestRing(Self.defaultRing)
        await waitUntil { self.hud.beganInteractively }
        XCTAssertEqual(hud.lastBeginCurrent, "2")
        XCTAssertEqual(hud.settleCount, 0)
    }

    func testSuppressionTimestampIsRecordedBeforeSwitch() async {
        loader.immediateRing = Self.defaultRing
        runner.holdNextSwitch()
        controller.handle(.began(.horizontal))
        controller.handle(.ended(.horizontal, steps: -1))
        await waitUntil { self.runner.switchTargets.count == 1 }

        let loadsBeforeFlash = loader.ringLoadCount
        let settlesBeforeFlash = hud.settleCount
        controller.showWorkspaceChangeHUD()
        await yieldMainActor()

        XCTAssertEqual(loader.ringLoadCount, loadsBeforeFlash)
        XCTAssertEqual(hud.settleCount, settlesBeforeFlash)
        runner.releaseSwitch()
        await waitUntil { self.switchedCount == 1 }
    }

    func testOldFailureDoesNotClearNewerCommitStamp() async {
        runner.holdNextSwitch()
        runner.failNextSwitch(ProcessRunnerError.executableNotFound("/missing/aerospace"))
        controller.handle(.began(.horizontal))
        await loader.waitUntilRingLoadCount(1)
        loader.completeOldestRing(Self.defaultRing)
        controller.handle(.ended(.horizontal, steps: -1))
        await waitUntil { self.runner.switchTargets.count == 1 }

        controller.handle(.began(.horizontal))
        controller.handle(.ended(.horizontal, steps: -1))
        runner.releaseSwitch()
        await loader.waitUntilRingLoadCount(2)

        let loadsBeforeFlash = loader.ringLoadCount
        controller.showWorkspaceChangeHUD()
        await yieldMainActor()
        XCTAssertEqual(loader.ringLoadCount, loadsBeforeFlash)
        XCTAssertEqual(switchedCount, 0)
    }

    func testSuccessfulSwitchInvokesWorkspaceSwitchedCallback() async {
        loader.immediateRing = Self.defaultRing
        controller.handle(.began(.horizontal))
        controller.handle(.ended(.horizontal, steps: -1))
        await waitUntil { self.switchedCount == 1 }
        XCTAssertEqual(runner.switchTargets, ["3"])
    }

    func testFailedSwitchDoesNotInvokeWorkspaceSwitchedCallback() async {
        loader.immediateRing = Self.defaultRing
        runner.failNextSwitch(ProcessRunnerError.executableNotFound("/missing/aerospace"))
        controller.handle(.began(.horizontal))
        controller.handle(.ended(.horizontal, steps: -1))
        await waitUntil { self.runner.switchTargets.count == 1 }
        await waitUntil { self.runner.focusedQueryCount >= 1 }
        XCTAssertEqual(switchedCount, 0)
    }

    func testHUDDisabledStillSwitches() async {
        preferences.showHUD = false
        loader.immediateRing = Self.defaultRing
        controller.handle(.began(.horizontal))
        await loader.waitUntilRingLoadCount(1)
        controller.handle(.ended(.horizontal, steps: -1))
        await waitUntil { self.switchedCount == 1 }

        XCTAssertEqual(runner.switchTargets, ["3"])
        XCTAssertTrue(hud.events.isEmpty)
        XCTAssertEqual(loader.ringRequests.last?.includePreviews, false)
    }

    func testOwnCommitSuppressesFlashForOneSecondThenAllowsIt() async {
        loader.immediateRing = Self.defaultRing
        controller.handle(.began(.horizontal))
        controller.handle(.ended(.horizontal, steps: -1))
        await waitUntil { self.switchedCount == 1 }
        let settlesAfterCommit = hud.settleCount

        controller.showWorkspaceChangeHUD()
        await yieldMainActor()
        XCTAssertEqual(hud.settleCount, settlesAfterCommit)

        clock.advance(WorkspaceChangeFlash.ownCommitSuppression)
        controller.showWorkspaceChangeHUD()
        await yieldMainActor()
        XCTAssertEqual(hud.settleCount, settlesAfterCommit)

        clock.advance(.milliseconds(1))
        controller.showWorkspaceChangeHUD()
        await waitUntil { self.hud.settleCount == settlesAfterCommit + 1 }
    }

    func testSkipEmptyAndPriorityAreForwardedToLoader() async throws {
        preferences.skipEmpty = false
        orderStore.order = ["Q", "W"]
        loader.immediateRing = Self.defaultRing
        controller.handle(.began(.horizontal))
        await loader.waitUntilRingLoadCount(1)

        let request = try XCTUnwrap(loader.ringRequests.last)
        XCTAssertEqual(request.skipEmpty, false)
        XCTAssertEqual(request.order, ["Q", "W"])
        XCTAssertEqual(request.includePreviews, true)
    }

    private func makeController() -> SwipeController {
        let created = SwipeController(
            client: AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner),
            workspaceOrder: orderStore,
            workspacePreview: { _ in nil },
            preferences: preferences,
            loader: loader,
            hud: hud,
            clock: clock.swipeClock
        )
        created.onWorkspaceSwitched = { [weak self] in
            self?.switchedCount += 1
        }
        return created
    }

    private static let defaultRing = loadedRing()

    private func loadedRing(
        workspaces: [String] = ["1", "2", "3"],
        current: String = "2",
        previews: [String: NSImage] = [:]
    ) -> SwipeWorkspaceLoader.LoadedRing {
        Self.loadedRing(workspaces: workspaces, current: current, previews: previews)
    }

    private static func loadedRing(
        workspaces: [String] = ["1", "2", "3"],
        current: String = "2",
        previews: [String: NSImage] = [:]
    ) -> SwipeWorkspaceLoader.LoadedRing {
        SwipeWorkspaceLoader.LoadedRing(
            ring: SwipeWorkspaceLoader.Ring(workspaces: workspaces, current: current),
            previews: previews
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !predicate() {
            if ContinuousClock.now >= deadline {
                XCTFail("timed out waiting for condition", file: file, line: line)
                return
            }
            await Task.yield()
        }
    }

    private func yieldMainActor() async {
        for _ in 0 ..< 8 {
            await Task.yield()
        }
    }
}

// MARK: - Test doubles

private final class FakeSwipeWorkspaceLoader: SwipeWorkspaceLoading, @unchecked Sendable {
    struct RingRequest: Equatable {
        var skipEmpty: Bool
        var order: [String]
        var includePreviews: Bool
    }

    var immediateRing: SwipeWorkspaceLoader.LoadedRing?
    var immediateIcons = SwipeWorkspaceLoader.LoadedIcons(icons: [:])

    private let lock = NSLock()
    private var pendingRings: [CheckedContinuation<SwipeWorkspaceLoader.LoadedRing, Never>] = []
    private var recordedRequests: [RingRequest] = []
    private var recordedLoadCount = 0

    var ringRequests: [RingRequest] {
        lock.withLock { recordedRequests }
    }

    var ringLoadCount: Int {
        lock.withLock { recordedLoadCount }
    }

    func loadRingAndPreviews(
        client _: AeroSpaceClient,
        skipEmpty: Bool,
        order: [String],
        includePreviews: Bool,
        preview _: @escaping @Sendable (String) -> NSImage?
    ) async -> SwipeWorkspaceLoader.LoadedRing {
        let request = RingRequest(skipEmpty: skipEmpty, order: order, includePreviews: includePreviews)
        if let immediateRing {
            noteRingLoad(request)
            return immediateRing
        }
        return await withCheckedContinuation { continuation in
            lock.lock()
            recordedRequests.append(request)
            recordedLoadCount += 1
            pendingRings.append(continuation)
            lock.unlock()
        }
    }

    func loadIcons(
        client _: AeroSpaceClient,
        icon _: @escaping @Sendable (WorkspaceApp) -> NSImage?
    ) async -> SwipeWorkspaceLoader.LoadedIcons {
        immediateIcons
    }

    func waitUntilRingLoadCount(
        _ count: Int,
        timeout: Duration = .seconds(1),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = ContinuousClock.now + timeout
        while lock.withLock({ recordedLoadCount }) < count {
            if ContinuousClock.now >= deadline {
                XCTFail("timed out waiting for ring load count \(count)", file: file, line: line)
                return
            }
            await Task.yield()
        }
    }

    func completeOldestRing(_ loaded: SwipeWorkspaceLoader.LoadedRing) {
        lock.lock()
        let continuation = pendingRings.isEmpty ? nil : pendingRings.removeFirst()
        lock.unlock()
        continuation?.resume(returning: loaded)
    }

    func cancelPendingRings() {
        lock.lock()
        let pending = pendingRings
        pendingRings.removeAll()
        lock.unlock()
        for continuation in pending {
            continuation.resume(returning: SwipeWorkspaceLoader.LoadedRing(ring: nil, previews: [:]))
        }
    }

    private func noteRingLoad(_ request: RingRequest) {
        lock.lock()
        recordedRequests.append(request)
        recordedLoadCount += 1
        lock.unlock()
    }
}

private final class ControllableCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var switchGate: DispatchSemaphore?
    private var switchError: (any Error)?
    private var recordedTargets: [String] = []
    private var lastFocused = "2"
    private var focusedQueries = 0

    var switchTargets: [String] {
        lock.withLock { recordedTargets }
    }

    var focusedQueryCount: Int {
        lock.withLock { focusedQueries }
    }

    func holdNextSwitch() {
        lock.lock()
        switchGate = DispatchSemaphore(value: 0)
        lock.unlock()
    }

    func failNextSwitch(_ error: any Error) {
        lock.lock()
        switchError = error
        lock.unlock()
    }

    func releaseSwitch() {
        lock.lock()
        let gate = switchGate
        lock.unlock()
        gate?.signal()
    }

    func run(_: String, arguments: [String]) throws -> ProcessResult {
        if arguments.first == "workspace" {
            let target = arguments.dropFirst().first ?? ""
            lock.lock()
            recordedTargets.append(target)
            lastFocused = target
            let gate = switchGate
            let error = switchError
            switchError = nil
            lock.unlock()
            gate?.wait()
            if let error {
                throw error
            }
            return Self.ok("")
        }
        if arguments.starts(with: ["list-workspaces", "--focused"]) {
            lock.lock()
            focusedQueries += 1
            let name = lastFocused
            lock.unlock()
            return Self.ok(name + "\n")
        }
        return Self.ok("")
    }

    private static func ok(_ output: String) -> ProcessResult {
        ProcessResult(standardOutput: output, standardError: "", terminationStatus: 0)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: ContinuousClock.Instant

    init(now: ContinuousClock.Instant = .now) {
        instant = now
    }

    var swipeClock: SwipeClock {
        SwipeClock(
            now: { self.lock.withLock { self.instant } },
            sleep: { _ in }
        )
    }

    func advance(_ duration: Duration) {
        lock.lock()
        instant += duration
        lock.unlock()
    }
}

@MainActor
private final class RecordingHUD: SwipeHUDEffects {
    enum Event: Equatable {
        case beginInteractive(workspaces: [String], current: String, wrapsAround: Bool)
        case setOffset(CGFloat)
        case settle(workspaces: [String], current: String, wrapsAround: Bool)
        case updateIcons
        case hide
    }

    private(set) var events: [Event] = []

    var settleCount: Int {
        events.filter { event in
            if case .settle = event {
                return true
            }
            return false
        }.count
    }

    var beganInteractively: Bool {
        events.contains { event in
            if case .beginInteractive = event {
                return true
            }
            return false
        }
    }

    var lastBeginCurrent: String? {
        events.reversed().compactMap { event in
            if case let .beginInteractive(_, current, _) = event {
                return current
            }
            return nil
        }.first
    }

    var offsets: [CGFloat] {
        events.compactMap { event in
            if case let .setOffset(offset) = event {
                return offset
            }
            return nil
        }
    }

    var wrapAroundOnSettle: Bool? {
        events.reversed().compactMap { event in
            if case let .settle(_, _, wrapsAround) = event {
                return wrapsAround
            }
            return nil
        }.first
    }

    func beginInteractive(
        workspaces: [String],
        current: String,
        previews _: [String: NSImage],
        wrapsAround: Bool
    ) {
        events.append(.beginInteractive(workspaces: workspaces, current: current, wrapsAround: wrapsAround))
    }

    func updateIcons(_: [String: [NSImage]]) {
        events.append(.updateIcons)
    }

    func setOffset(_ offset: CGFloat) {
        events.append(.setOffset(offset))
    }

    func settle(
        workspaces: [String],
        current: String,
        previews _: [String: NSImage],
        wrapsAround: Bool
    ) {
        events.append(.settle(workspaces: workspaces, current: current, wrapsAround: wrapsAround))
    }

    func hide() {
        events.append(.hide)
    }
}
