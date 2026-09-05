import AppKit
import CoreGraphics
import XCTest
@testable import AeroKitCore
@testable import ExposeFeature

final class ExposePresentationLoaderTests: XCTestCase {
    private func populatedRunner() -> PresentationCommandRunner {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = [
            presentationWindowLine(id: 101, title: "One", workspace: "1"),
            presentationWindowLine(id: 102, title: "Two", workspace: "1")
        ].joined(separator: "\n")
        runner.focusedWindowOutput = presentationFocusedLine(id: 101)
        runner.appWindowsOutput = [
            presentationWindowLine(id: 201, title: "App A", screen: 1, workspace: "1"),
            presentationWindowLine(id: 202, title: "App B", screen: 1, workspace: "2")
        ].joined(separator: "\n")
        runner.monitorWorkspacesOutput = [
            presentationWorkspaceLine(name: "1", focused: true),
            presentationWorkspaceLine(name: "2", focused: false)
        ].joined(separator: "\n")
        runner.allWorkspacesOutput = [
            presentationWorkspaceLine(name: "1", focused: true),
            presentationWorkspaceLine(name: "Q", focused: false)
        ].joined(separator: "\n")
        return runner
    }

    func testLoadSnapshotReturnsNilOnEmptyAndError() {
        XCTAssertNil(
            ExposePresentationLoader.loadSnapshot("workspace") {
                WorkspaceSnapshot(windows: [])
            }
        )

        struct Failure: Error {}
        XCTAssertNil(
            ExposePresentationLoader.loadSnapshot("workspace") {
                throw Failure()
            }
        )
    }

    func testLoadDropBarContentEmptyOnCLIFailure() {
        struct Failure: Error {}
        let content = ExposePresentationLoader.loadDropBarContent(
            preview: { _ in nil },
            { throw Failure() }
        )
        XCTAssertTrue(content.targets.isEmpty)
        XCTAssertTrue(content.previews.isEmpty)
    }

    func testWorkspaceContextLoadsWindowsDropBarAndBounds() async throws {
        let runner = populatedRunner()
        let boundsCalls = CallCounter()
        let bounds: [CGWindowID: CGRect] = [
            101: CGRect(x: 0, y: 0, width: 100, height: 80),
            102: CGRect(x: 120, y: 0, width: 100, height: 80)
        ]

        let context = await ExposePresentationLoader.workspaceContext(
            client: runner.makeClient(),
            windowBounds: {
                boundsCalls.increment()
                return bounds
            },
            preview: { _ in nil }
        )

        let loaded = try XCTUnwrap(context)
        XCTAssertEqual(loaded.snapshot.windows.map(\.id), [101, 102])
        XCTAssertEqual(loaded.focusedWindowID, 101)
        XCTAssertEqual(loaded.bounds, bounds)
        XCTAssertEqual(loaded.workspaceTargets.map(\.name), ["1", "2"])
        XCTAssertEqual(boundsCalls.count, 1)
        XCTAssertTrue(
            runner.invocations.contains { $0.starts(with: ["list-windows", "--workspace", "focused"]) }
        )
        XCTAssertTrue(
            runner.invocations.contains { $0.starts(with: ["list-windows", "--focused"]) }
        )
        XCTAssertTrue(
            runner.invocations.contains { $0.starts(with: ["list-workspaces", "--monitor", "focused"]) }
        )
    }

    func testWorkspaceContextSkipsBoundsWhenSnapshotIsEmpty() async {
        let runner = PresentationCommandRunner()
        runner.focusedWorkspaceWindowsOutput = ""
        runner.focusedWindowOutput = presentationFocusedLine(id: 1)
        let boundsCalls = CallCounter()

        let context = await ExposePresentationLoader.workspaceContext(
            client: runner.makeClient(),
            windowBounds: {
                boundsCalls.increment()
                return [:]
            },
            preview: { _ in nil }
        )

        XCTAssertNil(context)
        XCTAssertEqual(boundsCalls.count, 0)
    }

    func testWorkspaceContextReturnsNilOnListingError() async {
        let runner = populatedRunner()
        runner.failingPrefixes = [["list-windows", "--workspace", "focused"]]

        let context = await ExposePresentationLoader.workspaceContext(
            client: runner.makeClient(),
            windowBounds: { [:] },
            preview: { _ in nil }
        )

        XCTAssertNil(context)
    }

    func testWorkspaceQueriesOverlapOnBlockingWork() async {
        let runner = populatedRunner()
        runner.commandHold = 0.04

        let context = await ExposePresentationLoader.workspaceContext(
            client: runner.makeClient(),
            windowBounds: { [:] },
            preview: { _ in nil }
        )

        XCTAssertNotNil(context)
        XCTAssertGreaterThanOrEqual(
            runner.maxInFlight,
            2,
            "focused-window and drop-bar must overlap the workspace listing"
        )
        XCTAssertTrue(runner.events.contains("start workspace-windows"))
        XCTAssertTrue(runner.events.contains("start focused-window"))
        XCTAssertTrue(runner.events.contains("start monitor-workspaces"))
    }

    func testAppContextWaitsForFocusedWindowBeforeListingAppWindows() async throws {
        let runner = populatedRunner()
        runner.commandHold = 0.03
        runner.focusedWindowOutput = presentationFocusedLine(
            id: 201,
            bundle: "com.example.App",
            screen: 2
        )

        let context = await ExposePresentationLoader.appContext(
            client: runner.makeClient(),
            windowBounds: { [:] },
            preview: { _ in nil }
        )

        let loaded = try XCTUnwrap(context)
        XCTAssertEqual(loaded.snapshot.windows.map(\.id), [201, 202])
        XCTAssertEqual(loaded.focusedWindowID, 201)
        XCTAssertEqual(
            loaded.snapshot.screenNumber,
            2,
            "app exposé hosts the overlay on the focused window's screen"
        )
        XCTAssertEqual(loaded.workspaceTargets.map(\.name), ["1", "Q"])

        let focusedEnd = try XCTUnwrap(runner.events.firstIndex(of: "end focused-window"))
        let appStart = try XCTUnwrap(runner.events.firstIndex(of: "start app-windows"))
        XCTAssertLessThan(
            focusedEnd,
            appStart,
            "app window listing depends on the focused window's identity"
        )
        XCTAssertTrue(
            runner.invocations.contains {
                Array($0.prefix(5)) == [
                    "list-windows", "--monitor", "all", "--app-bundle-id", "com.example.App"
                ]
            }
        )
        XCTAssertTrue(runner.invocations.contains { $0.starts(with: ["list-workspaces", "--all"]) })
    }

    func testAppContextReturnsNilWithoutFocusedWindow() async {
        let runner = populatedRunner()
        runner.focusedWindowOutput = ""

        let context = await ExposePresentationLoader.appContext(
            client: runner.makeClient(),
            windowBounds: { [:] },
            preview: { _ in nil }
        )

        XCTAssertNil(context)
        XCTAssertFalse(runner.events.contains("start app-windows"))
    }

    func testDropBarPreviewLookupUsesInjectedClosure() async throws {
        let runner = populatedRunner()
        let image = NSImage(size: NSSize(width: 2, height: 2))
        let shared = PreviewImage(image: image)

        let context = await ExposePresentationLoader.workspaceContext(
            client: runner.makeClient(),
            windowBounds: { [:] },
            preview: { name in name == "1" ? shared.image : nil }
        )

        let loaded = try XCTUnwrap(context)
        XCTAssertIdentical(loaded.workspacePreviews["1"], image)
        XCTAssertNil(loaded.workspacePreviews["2"])
    }

    /// Immutable test-local fixture that shares one `NSImage` with a
    /// `@Sendable` preview closure. The image is never mutated while
    /// shared; `@unchecked` because NSImage is not Sendable on the
    /// macOS 15 SDK.
    private struct PreviewImage: @unchecked Sendable {
        let image: NSImage
    }
}
