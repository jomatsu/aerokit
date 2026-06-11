import XCTest
@testable import AeroKitCore

final class AeroSpaceClientFocusTests: XCTestCase {
    /// The unit separator AeroSpaceClient joins format fields with.
    private let us = "\u{1f}"

    private func makeClient(_ runner: StubRunner) -> AeroSpaceClient {
        AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)
    }

    // MARK: - focusedWorkspaceWindows

    func testParsesWindowsAndScreenNumber() throws {
        let runner = StubRunner(output: """
        101\(us)com.apple.Safari\(us)Safari\(us)Apple\(us)2
        102\(us)com.mitchellh.ghostty\(us)Ghostty\(us)tmux\(us)2
        """)

        let snapshot = try makeClient(runner).focusedWorkspaceWindows()

        XCTAssertEqual(snapshot.windows, [
            ExposeWindow(id: 101, bundleIdentifier: "com.apple.Safari", appName: "Safari", title: "Apple"),
            ExposeWindow(id: 102, bundleIdentifier: "com.mitchellh.ghostty", appName: "Ghostty", title: "tmux")
        ])
        XCTAssertEqual(snapshot.screenNumber, 2)
        XCTAssertEqual(runner.calls.first, [
            "list-windows", "--workspace", "focused", "--format",
            [
                "%{window-id}",
                "%{app-bundle-id}",
                "%{app-name}",
                "%{window-title}",
                "%{monitor-appkit-nsscreen-screens-id}"
            ].joined(separator: us)
        ])
    }

    func testSkipsMalformedLines() throws {
        let runner = StubRunner(output: """
        not-a-number\(us)a\(us)b\(us)c\(us)1
        103\(us)com.example\(us)Example\(us)\(us)1
        too\(us)few
        """)

        let snapshot = try makeClient(runner).focusedWorkspaceWindows()

        XCTAssertEqual(snapshot.windows.map(\.id), [103])
        XCTAssertEqual(snapshot.windows.first?.displayTitle, "Example", "Empty title falls back to the app name")
    }

    func testEmptyWorkspaceYieldsEmptySnapshot() throws {
        let snapshot = try makeClient(StubRunner(output: "")).focusedWorkspaceWindows()

        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertNil(snapshot.screenNumber)
    }

    // MARK: - focusedWindow

    func testFocusedWindowParsesAllFields() {
        let runner = StubRunner(output: "42\(us)com.apple.Safari\(us)1184\(us)2\n")

        let focused = makeClient(runner).focusedWindow()

        XCTAssertEqual(focused, FocusedWindow(
            id: 42,
            bundleIdentifier: "com.apple.Safari",
            pid: 1184,
            screenNumber: 2
        ))
        XCTAssertEqual(runner.calls.first, [
            "list-windows", "--focused", "--format",
            [
                "%{window-id}",
                "%{app-bundle-id}",
                "%{app-pid}",
                "%{monitor-appkit-nsscreen-screens-id}"
            ].joined(separator: us)
        ])
    }

    func testFocusedWindowToleratesEmptyBundleAndPid() {
        let focused = makeClient(StubRunner(output: "7\(us)\(us)\(us)1\n")).focusedWindow()

        XCTAssertEqual(focused, FocusedWindow(id: 7, bundleIdentifier: "", pid: nil, screenNumber: 1))
    }

    func testFocusedWindowIsNilWhenCommandFails() {
        XCTAssertNil(makeClient(StubRunner(error: StubRunner.Failure())).focusedWindow())
    }

    func testFocusedWindowIsNilOnEmptyOutput() {
        XCTAssertNil(makeClient(StubRunner(output: "")).focusedWindow())
    }

    // MARK: - appWindows

    func testAppWindowsFiltersByBundleIdentifier() throws {
        let runner = StubRunner(output: """
        201\(us)com.apple.Safari\(us)Safari\(us)Apple\(us)1
        202\(us)com.apple.Safari\(us)Safari\(us)Docs\(us)2
        """)

        let snapshot = try makeClient(runner).appWindows(bundleIdentifier: "com.apple.Safari", pid: 99)

        XCTAssertEqual(snapshot.windows.map(\.id), [201, 202])
        XCTAssertEqual(snapshot.screenNumber, 1)
        XCTAssertEqual(runner.calls.first?.prefix(5), [
            "list-windows", "--monitor", "all", "--app-bundle-id", "com.apple.Safari"
        ])
    }

    func testAppWindowsFallsBackToPidWithoutBundleIdentifier() throws {
        let runner = StubRunner(output: "")

        _ = try makeClient(runner).appWindows(bundleIdentifier: "", pid: 1184)

        XCTAssertEqual(runner.calls.first?.prefix(5), [
            "list-windows", "--monitor", "all", "--pid", "1184"
        ])
    }

    func testAppWindowsWithoutAnyFilterReturnsEmptySnapshot() throws {
        let runner = StubRunner(output: "ignored")

        let snapshot = try makeClient(runner).appWindows(bundleIdentifier: "", pid: nil)

        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertTrue(runner.calls.isEmpty, "No filter must not list every window on the system")
    }

    // MARK: - focusWindow

    func testFocusWindowPassesWindowID() throws {
        let runner = StubRunner(output: "")

        try makeClient(runner).focusWindow(id: 7)

        XCTAssertEqual(runner.calls, [["focus", "--window-id", "7"]])
    }

    // MARK: - summonWindow

    func testSummonWindowMovesToWorkspaceAndFocuses() throws {
        let runner = StubRunner(output: "")

        try makeClient(runner).summonWindow(id: 7, toWorkspace: "2")

        XCTAssertEqual(runner.calls, [
            ["move-node-to-workspace", "--focus-follows-window", "--window-id", "7", "2"]
        ])
    }

    // MARK: - focusedWorkspaceName

    func testFocusedWorkspaceNameTrimsOutput() throws {
        XCTAssertEqual(try makeClient(StubRunner(output: "Q\n")).focusedWorkspaceName(), "Q")
    }

    func testFocusedWorkspaceNameIsNilWhenEmpty() throws {
        XCTAssertNil(try makeClient(StubRunner(output: "\n")).focusedWorkspaceName())
    }
}

/// Test runner: replays a canned result and records every invocation.
/// `@unchecked Sendable` because tests drive it from a single thread.
private final class StubRunner: CommandRunning, @unchecked Sendable {
    struct Failure: Error {}

    private let result: Result<String, any Error>
    private(set) var calls: [[String]] = []

    init(output: String) {
        result = .success(output)
    }

    init(error: any Error) {
        result = .failure(error)
    }

    func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        calls.append(arguments)
        return try ProcessResult(
            standardOutput: result.get(),
            standardError: "",
            terminationStatus: 0
        )
    }
}
