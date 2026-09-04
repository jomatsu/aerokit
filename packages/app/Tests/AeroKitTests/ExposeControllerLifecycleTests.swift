import AppKit
import CoreGraphics
import XCTest
@testable import AeroKitCore
@testable import ExposeFeature

@MainActor
final class ExposeControllerLifecycleTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "ExposeControllerLifecycleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDismissDuringLoadDropsTheStaleResult() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeExposeHost()
        let controller = makeController(runner: runner, host: host)

        controller.toggle()
        XCTAssertTrue(controller.isActive, "load window counts as active")
        controller.toggle()
        XCTAssertFalse(controller.isActive)

        runner.release()
        await waitUntil { host.loadsFinished == 1 }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertEqual(host.digitStarts, 0)
        XCTAssertFalse(controller.isActive)
    }

    func testSwitchingScopeSupersedesTheInFlightWorkspaceLoad() async {
        let runner = populatedRunner()
        runner.holdUntilReleased()
        let host = FakeExposeHost()
        let controller = makeController(runner: runner, host: host)

        controller.toggle()
        controller.toggleAppWindows()
        runner.release()

        await waitUntil { host.loadsFinished == 2 }
        await waitUntil { host.sessions.count == 1 }

        XCTAssertEqual(host.edges, [.top])
        XCTAssertEqual(host.sessions[0].tiles.map(\.window.id), [201, 202])
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(host.digitStarts, 1)
        XCTAssertEqual(host.entryDeadlines, [120])
    }

    func testEmptyWorkspaceCleansUpWithoutShowingOrTapping() async {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = ""
        let host = FakeExposeHost()
        let controller = makeController(runner: runner, host: host)

        controller.toggle()
        await waitUntil { !controller.isActive }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertEqual(host.digitStarts, 0)
        XCTAssertEqual(host.hideCount, 0)
        XCTAssertTrue(host.entryDeadlines.isEmpty)
    }

    func testListingErrorCleansUpWithoutShowingOrTapping() async {
        let runner = populatedRunner()
        runner.failingPrefixes = [["list-windows", "--workspace", "focused"]]
        let host = FakeExposeHost()
        let controller = makeController(runner: runner, host: host)

        controller.toggle()
        await waitUntil { !controller.isActive }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertEqual(host.digitStarts, 0)
        XCTAssertTrue(host.entryDeadlines.isEmpty)
    }

    func testMissingScreenCleansUpWithoutShowing() async {
        let runner = populatedRunner()
        let host = FakeExposeHost()
        let controller = makeController(runner: runner, host: host) { _ in nil }

        controller.toggle()
        await waitUntil { !controller.isActive }

        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertEqual(host.digitStarts, 0)
    }

    func testEntryDeadlineDoesNotBeginEntryAfterDismiss() async {
        let runner = populatedRunner()
        let host = FakeExposeHost()
        let controller = makeController(runner: runner, host: host)

        controller.toggle()
        await waitUntil { host.sessions.count == 1 }
        XCTAssertEqual(host.entryDeadlines, [120])
        XCTAssertEqual(host.beginEntryCount, 0)

        controller.toggle()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(host.digitStops, 1)

        host.fireEntryDeadline()
        XCTAssertEqual(host.beginEntryCount, 0)
    }

    func testSuccessfulShowSchedulesThe120msEntryDeadline() async {
        let runner = populatedRunner()
        let host = FakeExposeHost()
        let controller = makeController(runner: runner, host: host)

        controller.toggle()
        await waitUntil { host.sessions.count == 1 }

        XCTAssertEqual(host.edges, [.bottom])
        XCTAssertEqual(host.sessions[0].tiles.map(\.window.id), [101, 102])
        XCTAssertEqual(host.entryDeadlines, [120])
        host.fireEntryDeadline()
        XCTAssertEqual(host.beginEntryCount, 1)
        XCTAssertTrue(controller.isActive)
    }

    private func populatedRunner() -> PresentationCommandRunner {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = [
            presentationWindowLine(id: 101, title: "One"),
            presentationWindowLine(id: 102, title: "Two")
        ].joined(separator: "\n")
        runner.focusedWindowOutput = presentationFocusedLine(id: 101)
        runner.appWindowsOutput = [
            presentationWindowLine(id: 201, title: "App A"),
            presentationWindowLine(id: 202, title: "App B")
        ].joined(separator: "\n")
        runner.monitorWorkspacesOutput = presentationWorkspaceLine(name: "1", focused: true)
        runner.allWorkspacesOutput = presentationWorkspaceLine(name: "1", focused: true)
        return runner
    }

    private func makeController(
        runner: PresentationCommandRunner,
        host: FakeExposeHost,
        resolveScreen: @escaping (Int?) -> NSScreen? = { PresentationScreenResolver.screen(for: $0) }
    ) -> ExposeController {
        let preferences = ExposePreferences(defaults: defaults)
        return ExposeController(
            client: runner.makeClient(),
            hotKeyCenter: HotKeyCenter(),
            preferences: preferences,
            hooks: host.hooks(resolveScreen: resolveScreen)
        )
    }
}

@MainActor
private final class FakeExposeHost {
    var isVisible = false
    var sessions: [ExposeSession] = []
    var edges: [ExposeOverlayMotion.Edge] = []
    var hideCount = 0
    var beginEntryCount = 0
    var digitStarts = 0
    var digitStops = 0
    var entryDeadlines: [Int] = []
    var loadsFinished = 0
    private var pendingEntry: [@MainActor () -> Void] = []

    func fireEntryDeadline() {
        let work = pendingEntry
        pendingEntry = []
        for item in work {
            item()
        }
    }

    func hooks(
        resolveScreen: @escaping (Int?) -> NSScreen?
    ) -> ExposeControllerHooks {
        ExposeControllerHooks(
            windowBounds: { [:] },
            resolveScreen: resolveScreen,
            isVisible: { [weak self] in self?.isVisible ?? false },
            show: { [weak self] session, _, _, edge in
                self?.sessions.append(session)
                self?.edges.append(edge)
                self?.isVisible = true
            },
            hide: { [weak self] in
                self?.hideCount += 1
                self?.isVisible = false
            },
            beginEntry: { [weak self] in
                self?.beginEntryCount += 1
            },
            isAccessibilityGranted: { true },
            startDigitTap: { [weak self] in
                self?.digitStarts += 1
                return true
            },
            stopDigitTap: { [weak self] in
                self?.digitStops += 1
            },
            scheduleEntryDeadline: { [weak self] milliseconds, work in
                self?.entryDeadlines.append(milliseconds)
                self?.pendingEntry.append(work)
            },
            presentationQueryFinished: { [weak self] in
                self?.loadsFinished += 1
            },
            capturesPreviews: false
        )
    }
}
