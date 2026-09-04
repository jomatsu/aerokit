import Foundation
import XCTest
@testable import AeroKitCore

/// Unit-separator AeroSpaceClient joins format fields with.
let presentationUS = "\u{1f}"

func presentationWindowLine(
    id: Int,
    bundle: String = "com.example.App",
    app: String = "App",
    title: String = "Title",
    screen: Int = 1,
    workspace: String = "1"
) -> String {
    [String(id), bundle, app, title, String(screen), workspace].joined(separator: presentationUS)
}

func presentationFocusedLine(
    id: Int,
    bundle: String = "com.example.App",
    pid: Int = 100,
    screen: Int = 1
) -> String {
    [String(id), bundle, String(pid), String(screen)].joined(separator: presentationUS)
}

func presentationWorkspaceLine(name: String, focused: Bool) -> String {
    [name, focused ? "true" : "false"].joined(separator: presentationUS)
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}

final class ThreadIdentity: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ObjectIdentifier?

    var current: ObjectIdentifier? {
        lock.withLock { value }
    }

    func capture() {
        lock.withLock { value = ObjectIdentifier(Thread.current) }
    }
}

/// Scripted AeroSpace CLI: canned outputs, optional gate, optional per-command
/// hold so overlapping BlockingWork hops can be observed.
final class PresentationCommandRunner: CommandRunning, @unchecked Sendable {
    struct Failure: Error {}

    var focusedWorkspaceWindowsOutput = ""
    var focusedWindowOutput = ""
    var appWindowsOutput = ""
    var monitorWorkspacesOutput = ""
    var allWorkspacesOutput = ""
    var failingPrefixes: [[String]] = []
    var commandHold: TimeInterval = 0

    private let lock = NSLock()
    private let condition = NSCondition()
    private var released = true
    private var recorded: [[String]] = []
    private var eventLog: [String] = []
    private var inFlight = 0
    private var completed = 0
    private var peakInFlight = 0
    private var cliThread: ObjectIdentifier?

    var invocations: [[String]] {
        lock.withLock { recorded }
    }

    var events: [String] {
        lock.withLock { eventLog }
    }

    var maxInFlight: Int {
        lock.withLock { peakInFlight }
    }

    var completedCount: Int {
        lock.withLock { completed }
    }

    var lastCLIThread: ObjectIdentifier? {
        lock.withLock { cliThread }
    }

    func holdUntilReleased() {
        condition.lock()
        released = false
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    func makeClient() -> AeroSpaceClient {
        AeroSpaceClient(executablePath: "/usr/bin/true", runner: self)
    }

    func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        lock.withLock {
            recorded.append(arguments)
            cliThread = ObjectIdentifier(Thread.current)
        }
        condition.lock()
        while !released {
            condition.wait()
        }
        condition.unlock()

        let name = Self.commandName(arguments)
        lock.lock()
        eventLog.append("start \(name)")
        inFlight += 1
        peakInFlight = max(peakInFlight, inFlight)
        lock.unlock()
        if commandHold > 0 {
            Thread.sleep(forTimeInterval: commandHold)
        }
        lock.lock()
        inFlight -= 1
        eventLog.append("end \(name)")
        completed += 1
        lock.unlock()

        if failingPrefixes.contains(where: { arguments.starts(with: $0) }) {
            throw Failure()
        }
        return ProcessResult(
            standardOutput: output(for: arguments),
            standardError: "",
            terminationStatus: 0
        )
    }

    private func output(for arguments: [String]) -> String {
        if arguments.starts(with: ["list-windows", "--workspace", "focused"]) {
            return focusedWorkspaceWindowsOutput
        }
        if arguments.starts(with: ["list-windows", "--focused"]) {
            return focusedWindowOutput
        }
        if arguments.starts(with: ["list-windows", "--monitor", "all"]) {
            return appWindowsOutput
        }
        if arguments.starts(with: ["list-workspaces", "--monitor", "focused"]) {
            return monitorWorkspacesOutput
        }
        if arguments.starts(with: ["list-workspaces", "--all"]) {
            return allWorkspacesOutput
        }
        return ""
    }

    private static func commandName(_ arguments: [String]) -> String {
        if arguments.starts(with: ["list-windows", "--workspace", "focused"]) {
            return "workspace-windows"
        }
        if arguments.starts(with: ["list-windows", "--focused"]) {
            return "focused-window"
        }
        if arguments.starts(with: ["list-windows", "--monitor", "all"]) {
            return "app-windows"
        }
        if arguments.starts(with: ["list-workspaces", "--monitor", "focused"]) {
            return "monitor-workspaces"
        }
        if arguments.starts(with: ["list-workspaces", "--all"]) {
            return "all-workspaces"
        }
        if arguments.first == "focus" {
            return "focus"
        }
        return arguments.prefix(3).joined(separator: " ")
    }
}

@MainActor
func waitUntil(
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("timed out waiting for condition", file: file, line: line)
}
