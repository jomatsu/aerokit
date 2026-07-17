import XCTest
@testable import AeroKitCore

final class AeroSpaceClientTests: XCTestCase {
    /// The unit separator AeroSpaceClient joins format fields with.
    private let us = "\u{1f}"

    // MARK: - listWorkspaces

    func testListWorkspacesParsesNamesAndFocus() throws {
        let runner = StubRunner(output: """
        1\(us)false
        2\(us)true
        Q\(us)false
        """)
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)

        let workspaces = try client.listWorkspaces()

        XCTAssertEqual(workspaces.map(\.name), ["1", "2", "Q"])
        XCTAssertEqual(workspaces.map(\.isFocused), [false, true, false])
    }

    func testListWorkspacesSkipsMalformedLines() throws {
        let runner = StubRunner(output: """
        1\(us)true

        \(us)true
        no-focus-field
        """)
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)

        let workspaces = try client.listWorkspaces()

        XCTAssertEqual(workspaces.map(\.name), ["1"])
    }

    func testListWorkspacesWithEmptyOutput() throws {
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: StubRunner(output: ""))

        XCTAssertTrue(try client.listWorkspaces().isEmpty)
    }

    // MARK: - workspacesOnFocusedMonitor

    func testWorkspacesOnFocusedMonitorParsesNamesAndFocus() throws {
        let runner = StubRunner(output: """
        1\(us)false
        2\(us)true
        """)
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)

        let workspaces = try client.workspacesOnFocusedMonitor(includeEmpty: true)

        XCTAssertEqual(workspaces.map(\.name), ["1", "2"])
        XCTAssertEqual(workspaces.map(\.isFocused), [false, true])
        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(invocation.arguments.prefix(4), ["list-workspaces", "--monitor", "focused", "--format"])
    }

    func testWorkspacesOnFocusedMonitorExcludesEmptyOnRequest() throws {
        let runner = StubRunner(output: "")
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)

        _ = try client.workspacesOnFocusedMonitor(includeEmpty: false)

        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(
            invocation.arguments.prefix(6),
            ["list-workspaces", "--monitor", "focused", "--empty", "no", "--format"]
        )
    }

    // MARK: - workspaceKeyBindings

    func testWorkspaceKeyBindingsParsesWorkspaceSwitchCommands() throws {
        let runner = StubRunner(output: """
        {
          "alt-1" : "workspace 1",
          "alt-e" : "summon-workspace Claude",
          "alt-shift-1" : "move-node-to-workspace 1",
          "alt-q" : ["exec-and-forget open -a Safari", "workspace Q"],
          "alt-b" : "workspace-back-and-forth",
          "alt-left" : "workspace --wrap-around prev",
          "alt-right" : "workspace --wrap-around next"
        }
        """)
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)

        let bindings = try client.workspaceKeyBindings()

        XCTAssertEqual(bindings, ["1": "alt-1", "Q": "alt-q", "Claude": "alt-e"])
        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(invocation.arguments, ["config", "--get", "mode.main.binding", "--json"])
    }

    func testWorkspaceKeyBindingsPreferFewestModifiersAndSkipOptions() throws {
        let runner = StubRunner(output: """
        {
          "alt-shift-2" : "workspace 2",
          "alt-2" : "workspace --auto-back-and-forth 2"
        }
        """)
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)

        XCTAssertEqual(try client.workspaceKeyBindings(), ["2": "alt-2"])
    }

    func testWorkspaceKeyBindingsWithUnparseableOutput() throws {
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: StubRunner(output: "not json"))

        XCTAssertEqual(try client.workspaceKeyBindings(), [:])
    }

    // MARK: - listWindows

    func testListWindowsParsesAllFields() throws {
        let fields = [
            "42", "com.apple.Safari", "Safari", "1", "Apple", "tiling", "h_tiles", "v_tiles"
        ].joined(separator: us)
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: StubRunner(output: fields))

        let window = try XCTUnwrap(client.listWindows().first)

        XCTAssertEqual(window.id, "42")
        XCTAssertEqual(window.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(window.appName, "Safari")
        XCTAssertEqual(window.workspace, "1")
        XCTAssertEqual(window.title, "Apple")
        XCTAssertEqual(window.layout, "tiling")
        XCTAssertEqual(window.parentContainerLayout, "h_tiles")
        XCTAssertEqual(window.workspaceRootContainerLayout, "v_tiles")
    }

    func testListWindowsPreservesEmptyFields() throws {
        // Windows without a bundle id or title still occupy their columns.
        let fields = ["7", "", "Helper", "2", "", "floating", "", ""].joined(separator: us)
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: StubRunner(output: fields))

        let window = try XCTUnwrap(client.listWindows().first)

        XCTAssertEqual(window.id, "7")
        XCTAssertEqual(window.bundleIdentifier, "")
        XCTAssertEqual(window.title, "")
        XCTAssertEqual(window.layout, "floating")
    }

    func testListWindowsFillsMissingLayoutColumns() throws {
        // Older aerospace builds emit only the first five columns.
        let fields = ["9", "com.example", "Example", "3", "Untitled"].joined(separator: us)
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: StubRunner(output: fields))

        let window = try XCTUnwrap(client.listWindows().first)

        XCTAssertEqual(window.id, "9")
        XCTAssertEqual(window.layout, "")
        XCTAssertEqual(window.parentContainerLayout, "")
        XCTAssertEqual(window.workspaceRootContainerLayout, "")
    }

    func testListWindowsSkipsShortAndBlankLines() throws {
        let valid = ["1", "com.example", "Example", "1", "Title"].joined(separator: us)
        let runner = StubRunner(output: """
        \(valid)

        too\(us)few\(us)fields
        """)
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)

        let windows = try client.listWindows()

        XCTAssertEqual(windows.map(\.id), ["1"])
    }

    // MARK: - Invocations & errors

    func testSwitchToWorkspacePassesArguments() throws {
        let runner = StubRunner(output: "")
        let client = AeroSpaceClient(executablePath: "/opt/homebrew/bin/aerospace", runner: runner)

        try client.switchToWorkspace("Q")

        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/aerospace")
        XCTAssertEqual(invocation.arguments, ["workspace", "Q"])
    }

    func testListWindowsRequestsExpectedFormat() throws {
        let runner = StubRunner(output: "")
        let client = AeroSpaceClient(executablePath: "/usr/bin/true", runner: runner)

        _ = try client.listWindows()

        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(invocation.arguments.prefix(3), ["list-windows", "--all", "--format"])
        XCTAssertEqual(invocation.arguments.count, 4)
    }

    func testRunnerErrorsPropagate() {
        let failure = ProcessRunnerError.executableNotFound("/missing/aerospace")
        let client = AeroSpaceClient(executablePath: "/missing/aerospace", runner: StubRunner(error: failure))

        XCTAssertThrowsError(try client.listWorkspaces())
        XCTAssertThrowsError(try client.listWindows())
        XCTAssertThrowsError(try client.switchToWorkspace("1"))
    }
}

/// Records invocations and replays a canned result.
/// `@unchecked` because the invocation list is guarded by `lock`.
private final class StubRunner: CommandRunning, @unchecked Sendable {
    struct Invocation {
        let executable: String
        let arguments: [String]
    }

    private let result: Result<ProcessResult, any Error>
    private let lock = NSLock()
    private var recordedInvocations: [Invocation] = []

    var invocations: [Invocation] {
        lock.withLock { recordedInvocations }
    }

    init(output: String) {
        result = .success(ProcessResult(standardOutput: output, standardError: "", terminationStatus: 0))
    }

    init(error: any Error) {
        result = .failure(error)
    }

    func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        lock.withLock {
            recordedInvocations.append(Invocation(executable: executable, arguments: arguments))
        }
        return try result.get()
    }
}
