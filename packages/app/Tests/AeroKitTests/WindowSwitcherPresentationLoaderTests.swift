import CoreGraphics
import XCTest
@testable import AeroKitCore
@testable import ExposeFeature

final class WindowSwitcherPresentationLoaderTests: XCTestCase {
    private func populatedRunner() -> PresentationCommandRunner {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = [
            presentationWindowLine(id: 11, title: "A"),
            presentationWindowLine(id: 12, title: "B")
        ].joined(separator: "\n")
        runner.focusedWindowOutput = presentationFocusedLine(id: 11)
        return runner
    }

    func testLoadReturnsSnapshotFocusedStackingAndBounds() async throws {
        let runner = populatedRunner()
        let stackingCalls = CallCounter()
        let boundsCalls = CallCounter()
        let stacking: [CGWindowID] = [12, 11, 99]
        let bounds: [CGWindowID: CGRect] = [11: CGRect(x: 0, y: 0, width: 40, height: 20)]
        let stackingThread = ThreadIdentity()

        let context = await WindowSwitcherPresentationLoader.load(
            client: runner.makeClient(),
            stacking: {
                stackingCalls.increment()
                stackingThread.capture()
                return stacking
            },
            bounds: {
                boundsCalls.increment()
                return bounds
            }
        )

        let loaded = try XCTUnwrap(context)
        XCTAssertEqual(loaded.snapshot.windows.map(\.id), [11, 12])
        XCTAssertEqual(loaded.focusedID, 11)
        XCTAssertEqual(loaded.stacking, stacking)
        XCTAssertEqual(loaded.bounds, bounds)
        XCTAssertEqual(stackingCalls.count, 1)
        XCTAssertEqual(boundsCalls.count, 1)
        XCTAssertEqual(
            stackingThread.current,
            runner.lastCLIThread,
            "stacking/bounds must share the snapshot's BlockingWork hop"
        )
        XCTAssertEqual(
            runner.invocations.map { Array($0.prefix(2)) },
            [
                ["list-windows", "--workspace"],
                ["list-windows", "--focused"]
            ]
        )
        XCTAssertEqual(
            Array(runner.invocations[0].prefix(3)),
            ["list-windows", "--workspace", "focused"]
        )
    }

    func testLoadSkipsWindowServerQueriesWhenSnapshotIsEmpty() async {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = ""
        runner.focusedWindowOutput = presentationFocusedLine(id: 1)
        let stackingCalls = CallCounter()
        let boundsCalls = CallCounter()

        let context = await WindowSwitcherPresentationLoader.load(
            client: runner.makeClient(),
            stacking: {
                stackingCalls.increment()
                return []
            },
            bounds: {
                boundsCalls.increment()
                return [:]
            }
        )

        XCTAssertNil(context)
        XCTAssertEqual(stackingCalls.count, 0)
        XCTAssertEqual(boundsCalls.count, 0)
        XCTAssertFalse(runner.events.contains("start focused-window"))
    }

    func testLoadReturnsNilOnListingError() async {
        let runner = populatedRunner()
        runner.failingPrefixes = [["list-windows", "--workspace", "focused"]]
        let stackingCalls = CallCounter()

        let context = await WindowSwitcherPresentationLoader.load(
            client: runner.makeClient(),
            stacking: {
                stackingCalls.increment()
                return []
            },
            bounds: { [:] }
        )

        XCTAssertNil(context)
        XCTAssertEqual(stackingCalls.count, 0)
    }
}
