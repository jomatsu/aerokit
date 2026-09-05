import AppKit
import XCTest
@testable import AeroKitCore
@testable import SwipeFeature

final class SwipeWorkspaceLoaderTests: XCTestCase {
    private let us = "\u{1f}"
    private let loader = SwipeWorkspaceLoader()

    func testLoadRingPreservesListingOrderWhenPriorityIsEmpty() throws {
        let runner = ScriptedCommandRunner()
        runner.listWorkspacesOutput = workspaceList([
            ("1", false),
            ("10", false),
            ("2", true)
        ])
        let ring = loader.loadRing(client: client(runner), skipEmpty: true, order: [])

        XCTAssertEqual(ring, SwipeWorkspaceLoader.Ring(workspaces: ["1", "10", "2"], current: "2"))
        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(
            Array(invocation.prefix(6)),
            ["list-workspaces", "--monitor", "focused", "--empty", "no", "--format"]
        )
        XCTAssertFalse(runner.invocations.contains { $0.starts(with: ["list-workspaces", "--focused"]) })
    }

    func testLoadRingIncludesEmptyWorkspacesWhenSkipEmptyIsOff() throws {
        let runner = ScriptedCommandRunner()
        runner.listWorkspacesOutput = workspaceList([("1", true), ("2", false)])
        _ = loader.loadRing(client: client(runner), skipEmpty: false, order: [])

        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(Array(invocation.prefix(4)), ["list-workspaces", "--monitor", "focused", "--format"])
        XCTAssertFalse(invocation.contains("--empty"))
    }

    func testLoadRingInsertsMissingCurrentInNaturalOrder() {
        // Skip-empty dropped the focused workspace "2" from the listing.
        let runner = ScriptedCommandRunner()
        runner.listWorkspacesOutput = workspaceList([("1", false), ("3", false), ("10", false)])
        runner.focusedWorkspaceOutput = "2"
        let ring = loader.loadRing(client: client(runner), skipEmpty: true, order: [])

        XCTAssertEqual(ring, SwipeWorkspaceLoader.Ring(workspaces: ["1", "2", "3", "10"], current: "2"))
        XCTAssertTrue(runner.invocations.contains { $0.starts(with: ["list-workspaces", "--focused"]) })
    }

    func testLoadRingAppliesPriorityOrderAndInsertsMissingCurrent() {
        let runner = ScriptedCommandRunner()
        runner.listWorkspacesOutput = workspaceList([("1", false), ("2", false)])
        runner.focusedWorkspaceOutput = "W"
        let ring = loader.loadRing(
            client: client(runner),
            skipEmpty: true,
            order: ["W", "1"]
        )

        XCTAssertEqual(ring, SwipeWorkspaceLoader.Ring(workspaces: ["W", "1", "2"], current: "W"))
    }

    func testLoadRingReturnsNilWhenListingFails() {
        let runner = ScriptedCommandRunner()
        runner.listWorkspacesError = ProcessRunnerError.executableNotFound("/missing/aerospace")
        XCTAssertNil(loader.loadRing(client: client(runner), skipEmpty: true, order: []))
    }

    func testLoadRingReturnsNilWhenNoCurrentWorkspaceIsAvailable() {
        let runner = ScriptedCommandRunner()
        runner.listWorkspacesOutput = ""
        runner.focusedWorkspaceOutput = ""
        XCTAssertNil(loader.loadRing(client: client(runner), skipEmpty: true, order: []))
    }

    func testLoadPreviewsOmitNilImages() {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        let previews = loader.loadPreviews(workspaces: ["1", "2", "3"]) { name in
            name == "2" ? image : nil
        }

        XCTAssertEqual(Set(previews.keys), ["2"])
        XCTAssertIdentical(previews["2"], image)
    }

    func testLoadIconsGroupsUniqueAppsInWindowOrder() throws {
        let runner = ScriptedCommandRunner()
        runner.listWindowsOutput = [
            windowLine(id: "1", bundle: "com.apple.Safari", app: "Safari", workspace: "1"),
            windowLine(id: "2", bundle: "com.apple.Safari", app: "Safari", workspace: "1"),
            windowLine(id: "3", bundle: "com.apple.mail", app: "Mail", workspace: "1"),
            windowLine(id: "4", bundle: "com.apple.Terminal", app: "Terminal", workspace: "2")
        ].joined(separator: "\n")
        let safari = NSImage(size: NSSize(width: 1, height: 1))
        let terminal = NSImage(size: NSSize(width: 1, height: 1))

        let icons = loader.loadIcons(client: client(runner)) { app in
            switch app.bundleIdentifier {
            case "com.apple.Safari": safari
            case "com.apple.Terminal": terminal
            default: nil
            }
        }

        XCTAssertIdentical(icons["1"]?.first, safari)
        XCTAssertEqual(icons["1"]?.count, 1)
        XCTAssertIdentical(icons["2"]?.first, terminal)
        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(Array(invocation.prefix(2)), ["list-windows", "--all"])
    }

    func testLoadIconsReturnsEmptyDictionaryWhenListingFails() {
        let runner = ScriptedCommandRunner()
        runner.listWindowsError = ProcessRunnerError.executableNotFound("/missing/aerospace")
        let icons = loader.loadIcons(client: client(runner)) { _ in
            XCTFail("icon resolution should not run after a listing failure")
            return nil
        }
        XCTAssertTrue(icons.isEmpty)
    }

    func testAsyncLoadRingAndPreviewsSkipsPreviewWorkWhenNotRequested() async {
        let runner = ScriptedCommandRunner()
        runner.listWorkspacesOutput = workspaceList([("1", false), ("2", true), ("3", false)])
        let calls = PreviewCallCounter()

        let loaded = await loader.loadRingAndPreviews(
            client: client(runner),
            skipEmpty: true,
            order: [],
            includePreviews: false
        ) { _ in
            calls.increment()
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        XCTAssertEqual(loaded.ring?.workspaces, ["1", "2", "3"])
        XCTAssertEqual(loaded.ring?.current, "2")
        XCTAssertTrue(loaded.previews.isEmpty)
        XCTAssertEqual(calls.count, 0)
    }

    func testAsyncLoadRingAndPreviewsFillsThumbnailsWhenRequested() async {
        let runner = ScriptedCommandRunner()
        runner.listWorkspacesOutput = workspaceList([("1", true)])
        let image = NSImage(size: NSSize(width: 1, height: 1))
        let shared = PreviewImage(image: image)

        let loaded = await loader.loadRingAndPreviews(
            client: client(runner),
            skipEmpty: false,
            order: [],
            includePreviews: true
        ) { name in
            name == "1" ? shared.image : nil
        }

        XCTAssertIdentical(loaded.previews["1"], image)
    }

    private func client(_ runner: ScriptedCommandRunner) -> AeroSpaceClient {
        AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)
    }

    private func workspaceList(_ rows: [(String, Bool)]) -> String {
        rows.map { "\($0.0)\(us)\($0.1 ? "true" : "false")" }.joined(separator: "\n")
    }

    private func windowLine(id: String, bundle: String, app: String, workspace: String) -> String {
        [id, bundle, app, workspace, "Title", "tiling", "h_tiles", "v_tiles"].joined(separator: us)
    }

    /// Immutable test-local fixture that shares one `NSImage` with a
    /// `@Sendable` preview closure. The image is never mutated while
    /// shared; `@unchecked` because NSImage is not Sendable on the
    /// macOS 15 SDK.
    private struct PreviewImage: @unchecked Sendable {
        let image: NSImage
    }

    /// Counts preview-closure invocations off the main actor; lock-guarded
    /// because `loadRingAndPreviews` hops through BlockingWork.
    private final class PreviewCallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        var count: Int {
            lock.withLock { value }
        }

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }
    }
}

/// Records invocations and replays canned AeroSpace listings.
private final class ScriptedCommandRunner: CommandRunning, @unchecked Sendable {
    var listWorkspacesOutput = ""
    var focusedWorkspaceOutput = ""
    var listWindowsOutput = ""
    var listWorkspacesError: (any Error)?
    var listWindowsError: (any Error)?

    private let lock = NSLock()
    private var recorded: [[String]] = []

    var invocations: [[String]] {
        lock.withLock { recorded }
    }

    func run(_: String, arguments: [String]) throws -> ProcessResult {
        lock.withLock { recorded.append(arguments) }
        if arguments.first == "list-windows" {
            if let listWindowsError {
                throw listWindowsError
            }
            return Self.ok(listWindowsOutput)
        }
        if arguments.starts(with: ["list-workspaces", "--focused"]) {
            return Self.ok(focusedWorkspaceOutput)
        }
        if arguments.starts(with: ["list-workspaces", "--monitor", "focused"]) {
            if let listWorkspacesError {
                throw listWorkspacesError
            }
            return Self.ok(listWorkspacesOutput)
        }
        return Self.ok("")
    }

    private static func ok(_ output: String) -> ProcessResult {
        ProcessResult(standardOutput: output, standardError: "", terminationStatus: 0)
    }
}
