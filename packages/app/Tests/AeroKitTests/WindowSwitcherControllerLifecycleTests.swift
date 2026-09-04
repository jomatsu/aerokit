import AppKit
import CoreGraphics
import XCTest
@testable import AeroKitCore
@testable import ExposeFeature

@MainActor
final class WindowSwitcherControllerLifecycleTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "WindowSwitcherControllerLifecycleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "expose.windowSwitchEnabled")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDisabledByDefaultIgnoresCycleHotkeys() {
        defaults.set(false, forKey: "expose.windowSwitchEnabled")
        let runner = PresentationCommandRunner()
        let host = FakeSwitcherHost()
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(runner.invocations.isEmpty)
        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertTrue(host.events.isEmpty)
    }

    func testTapUnregistersCarbonAtOpenAndReregistersOnDismiss() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost(mode: .tapSucceeds)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertEqual(host.events, [.tapStart] + carbonOff)
        XCTAssertTrue(controller.isActive)

        runner.release()
        await waitUntil { host.sessions.count == 1 }
        XCTAssertEqual(host.events, [.tapStart] + carbonOff, "tap path must not wait until show to drop Carbon")

        controller.cancelIfActive()
        XCTAssertEqual(host.events, [.tapStart] + carbonOff + [.tapStop] + carbonOn)
        XCTAssertFalse(controller.isActive)
    }

    func testFallbackKeepsCarbonThroughLoadThenReleasesAfterShow() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost(mode: .accessibilityDenied)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertEqual(host.events, [.dismissorBegin])
        XCTAssertTrue(controller.isActive)

        runner.release()
        await waitUntil { host.sessions.count == 1 }
        XCTAssertEqual(
            host.events,
            [.dismissorBegin] + carbonOff,
            "fallback keeps Carbon registered through the load, then releases after show"
        )

        controller.cancelIfActive()
        XCTAssertEqual(host.events, [.dismissorBegin] + carbonOff + [.dismissorEnd] + carbonOn)
    }

    func testTapInstallFailureFollowsFallbackCarbonOwnership() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost(mode: .tapInstallFails)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertEqual(host.events, [.tapStart, .dismissorBegin])

        runner.release()
        await waitUntil { host.sessions.count == 1 }
        XCTAssertEqual(host.events, [.tapStart, .dismissorBegin] + carbonOff)

        controller.cancelIfActive()
        XCTAssertEqual(
            host.events,
            [.tapStart, .dismissorBegin] + carbonOff + [.dismissorEnd] + carbonOn
        )
        XCTAssertFalse(host.events.contains(.tapStop), "a failed start is not stored, so dismiss must not stop it")
    }

    func testDismissDuringTapLoadDropsTheStaleResult() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost(mode: .tapSucceeds)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        controller.cancelIfActive()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(host.events.last, .register(.windowCycleBackward))

        runner.release()
        await waitUntil { host.loadsFinished == 1 }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertEqual(host.hideCount, 1)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
    }

    func testDismissDuringFallbackLoadDropsTheStaleResult() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost(mode: .accessibilityDenied)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertEqual(host.events, [.dismissorBegin])
        controller.cancelIfActive()
        XCTAssertEqual(host.events, [.dismissorBegin, .dismissorEnd] + carbonOn)

        runner.release()
        await waitUntil { host.loadsFinished == 1 }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
    }

    func testPendingCarbonRepeatsDuringFallbackLoadAreAppliedWhenTheSessionLands() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost(mode: .accessibilityDenied)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        XCTAssertEqual(host.events, [.dismissorBegin], "Carbon must still be the repeat path during fallback load")
        controller.handle(.windowCycleBackward)
        controller.handle(.windowCycleBackward)
        runner.release()

        await waitUntil { host.sessions.count == 1 }

        // Opening .next lands on 12; two extra previous moves wrap 12 → 11 → 13.
        XCTAssertEqual(host.sessions[0].selectedEntry?.id, 13)
        XCTAssertTrue(controller.isActive)
    }

    func testCycleTapDuringLoadIsAppliedWhenTheSessionLands() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost(mode: .tapSucceeds)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        host.cycleTap.onMove?(.next)
        runner.release()

        await waitUntil { host.sessions.count == 1 }

        XCTAssertEqual(host.sessions[0].selectedEntry?.id, 13)
    }

    func testTapReleaseDuringLoadShowsThenCommitsAfter100ms() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost(mode: .tapSucceeds)
        let controller = makeController(runner: runner, host: host, modifiersHeld: true)

        controller.handle(.windowCycleForward)
        host.cycleTap.onCommit?()
        XCTAssertTrue(host.sessions.isEmpty)
        runner.release()

        await waitUntil { host.sessions.count == 1 }

        XCTAssertEqual(host.quickTapDelays, [0.1])
        XCTAssertEqual(host.hideCount, 0)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
        XCTAssertTrue(controller.isActive)

        host.fireQuickTapCommit()
        await waitUntil { host.hideCount == 1 }

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(host.events.contains(.tapStop))
        await waitUntil { runner.invocations.contains { $0 == ["focus", "--window-id", "12"] } }
        XCTAssertEqual(Array(host.events.suffix(4)), carbonOn)
    }

    func testFallbackReleaseDuringLoadShowsThenCommitsAfter100ms() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeSwitcherHost(mode: .accessibilityDenied)
        let controller = makeController(runner: runner, host: host, modifiersHeld: true)

        controller.handle(.windowCycleForward)
        host.holdDismiss.onModifierRelease?()
        runner.release()

        await waitUntil { host.sessions.count == 1 }
        XCTAssertEqual(host.quickTapDelays, [0.1])
        XCTAssertEqual(host.hideCount, 0)

        host.fireQuickTapCommit()
        await waitUntil { host.hideCount == 1 }
        await waitUntil { runner.invocations.contains { $0.first == "focus" } }

        XCTAssertTrue(host.events.contains(.dismissorEnd))
        XCTAssertEqual(Array(host.events.suffix(4)), carbonOn)
    }

    func testQuickTapShowsBeforeTheDelayedCommit() async {
        let runner = populatedRunner()
        let host = FakeSwitcherHost(mode: .tapSucceeds)
        let controller = makeController(runner: runner, host: host, modifiersHeld: false)

        controller.handle(.windowCycleForward)
        await waitUntil { host.sessions.count == 1 }

        XCTAssertEqual(host.quickTapDelays, [0.1], "quick-tap commit stays a 100ms delay")
        XCTAssertEqual(host.hideCount, 0)
        XCTAssertTrue(controller.isActive)
        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })

        host.fireQuickTapCommit()
        await waitUntil { host.hideCount == 1 }
        await waitUntil { runner.invocations.contains { $0.first == "focus" } }

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(host.sessions[0].selectedEntry?.id, 12)
    }

    func testQuickTapCommitIsDroppedIfDismissedBeforeTheDelay() async {
        let runner = populatedRunner()
        let host = FakeSwitcherHost(mode: .tapSucceeds)
        let controller = makeController(runner: runner, host: host, modifiersHeld: false)

        controller.handle(.windowCycleForward)
        await waitUntil { host.sessions.count == 1 }
        controller.cancelIfActive()
        XCTAssertFalse(controller.isActive)

        host.fireQuickTapCommit()

        XCTAssertFalse(runner.invocations.contains { $0.first == "focus" })
    }

    func testEmptyResultStopsTheCycleTapAndReregistersCarbon() async {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = ""
        let host = FakeSwitcherHost(mode: .tapSucceeds)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        await waitUntil { host.loadsFinished == 1 }
        await waitUntil { !controller.isActive }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertEqual(host.events, [.tapStart] + carbonOff + [.tapStop] + carbonOn)
        XCTAssertEqual(host.hideCount, 1)
    }

    func testEmptyFallbackEndsDismissorAndReregistersCarbon() async {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = ""
        let host = FakeSwitcherHost(mode: .accessibilityDenied)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        await waitUntil { host.loadsFinished == 1 }
        await waitUntil { !controller.isActive }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertEqual(host.events, [.dismissorBegin, .dismissorEnd] + carbonOn)
    }

    func testListingErrorStopsTheCycleTap() async {
        let runner = populatedRunner()
        runner.failingPrefixes = [["list-windows", "--workspace", "focused"]]
        let host = FakeSwitcherHost(mode: .tapSucceeds)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        await waitUntil { host.loadsFinished == 1 }
        await waitUntil { !controller.isActive }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertEqual(host.events, [.tapStart] + carbonOff + [.tapStop] + carbonOn)
    }

    func testListingErrorOnFallbackEndsDismissor() async {
        let runner = populatedRunner()
        runner.failingPrefixes = [["list-windows", "--workspace", "focused"]]
        let host = FakeSwitcherHost(mode: .accessibilityDenied)
        let controller = makeController(runner: runner, host: host)

        controller.handle(.windowCycleForward)
        await waitUntil { host.loadsFinished == 1 }
        await waitUntil { !controller.isActive }

        XCTAssertEqual(host.events, [.dismissorBegin, .dismissorEnd] + carbonOn)
    }

    private var carbonOff: [SwitcherTrace] {
        [.unregister(.windowCycleForward), .unregister(.windowCycleBackward)]
    }

    private var carbonOn: [SwitcherTrace] {
        [
            .unregister(.windowCycleForward),
            .unregister(.windowCycleBackward),
            .register(.windowCycleForward),
            .register(.windowCycleBackward)
        ]
    }

    private func populatedRunner() -> PresentationCommandRunner {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = [
            presentationWindowLine(id: 11, title: "A"),
            presentationWindowLine(id: 12, title: "B"),
            presentationWindowLine(id: 13, title: "C")
        ].joined(separator: "\n")
        runner.focusedWindowOutput = presentationFocusedLine(id: 11)
        return runner
    }

    private func makeController(
        runner: PresentationCommandRunner,
        host: FakeSwitcherHost,
        modifiersHeld: Bool = true
    ) -> WindowSwitcherController {
        WindowSwitcherController(
            client: runner.makeClient(),
            preferences: ExposePreferences(defaults: defaults),
            hooks: host.hooks(
                modifiersHeld: modifiersHeld,
                stacking: [11, 12, 13]
            )
        )
    }
}

private enum SwitcherTrace: Equatable {
    case tapStart
    case tapStop
    case dismissorBegin
    case dismissorEnd
    case unregister(HotKeyRole)
    case register(HotKeyRole)
}

private enum SwitcherInteractionMode {
    case tapSucceeds
    case tapInstallFails
    case accessibilityDenied
}

@MainActor
private final class FakeSwitcherHost {
    let cycleTap = FakeCycleTap()
    let holdDismiss = FakeHoldDismiss()
    let hotKeys = RecordingHotKeys()
    var events: [SwitcherTrace] = []
    var isVisible = false
    var sessions: [WindowCycleSession] = []
    var hideCount = 0
    var loadsFinished = 0
    var quickTapDelays: [TimeInterval] = []
    private var pendingCommit: [() -> Void] = []
    private let mode: SwitcherInteractionMode

    init(mode: SwitcherInteractionMode = .tapSucceeds) {
        self.mode = mode
        cycleTap.host = self
        cycleTap.startSucceeds = mode != .tapInstallFails
        holdDismiss.host = self
        hotKeys.host = self
    }

    func fireQuickTapCommit() {
        let work = pendingCommit
        pendingCommit = []
        for item in work {
            item()
        }
    }

    func hooks(
        modifiersHeld: Bool,
        stacking: [CGWindowID]
    ) -> WindowSwitcherControllerHooks {
        WindowSwitcherControllerHooks(
            windowBounds: { [:] },
            stacking: { stacking },
            resolveScreen: { PresentationScreenResolver.screen(for: $0) },
            isVisible: { [weak self] in self?.isVisible ?? false },
            show: { [weak self] session, _, _ in
                self?.sessions.append(session)
                self?.isVisible = true
            },
            hide: { [weak self] in
                self?.hideCount += 1
                self?.isVisible = false
            },
            modifiersHeld: { _ in modifiersHeld },
            isAccessibilityGranted: { [weak self] in
                guard let self else {
                    return false
                }
                return mode != .accessibilityDenied
            },
            makeCycleTap: { [weak self] _ in
                guard let self else {
                    return FakeCycleTap()
                }
                return cycleTap
            },
            makeHoldDismiss: { [weak self] _, _ in
                guard let self else {
                    return FakeHoldDismiss()
                }
                return holdDismiss
            },
            hotKeys: hotKeys,
            scheduleQuickTapCommit: { [weak self] delay, work in
                self?.quickTapDelays.append(delay)
                self?.pendingCommit.append(work)
            },
            presentationQueryFinished: { [weak self] in
                self?.loadsFinished += 1
            },
            capturesPreviews: false
        )
    }
}

@MainActor
private final class FakeCycleTap: WindowCycleTapping {
    weak var host: FakeSwitcherHost?
    var startSucceeds = true
    var onMove: ((SelectionMove) -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    func start() -> Bool {
        host?.events.append(.tapStart)
        return startSucceeds
    }

    func stop() {
        host?.events.append(.tapStop)
    }
}

@MainActor
private final class FakeHoldDismiss: HoldToCommitDismissing {
    weak var host: FakeSwitcherHost?
    var onModifierRelease: (() -> Void)?

    func beginSession() {
        host?.events.append(.dismissorBegin)
    }

    func endSession() {
        host?.events.append(.dismissorEnd)
    }

    func noteKeyEvent(_: NSEvent) {}
}

@MainActor
private final class RecordingHotKeys: WindowSwitcherHotKeyRegistering {
    weak var host: FakeSwitcherHost?

    func register(_ role: HotKeyRole, keyCode: UInt32, modifiers: UInt32) throws {
        host?.events.append(.register(role))
    }

    func unregister(_ role: HotKeyRole) {
        host?.events.append(.unregister(role))
    }
}
