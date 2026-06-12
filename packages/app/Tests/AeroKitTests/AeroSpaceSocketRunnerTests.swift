import Darwin
import XCTest
@testable import AeroKitCore

final class AeroSpaceSocketRunnerTests: XCTestCase {
    func testReturnsServerAnswerOverSocket() throws {
        let server = try MiniSocketServer(
            respond: #"{"exitCode":0,"stdout":"1\n2\n","stderr":"","serverVersionAndHash":"test"}"#
        )
        let runner = AeroSpaceSocketRunner(socketPath: server.path, fallback: FailingRunner())

        let result = try runner.run("/usr/bin/aerospace", arguments: ["list-workspaces", "--all"])

        XCTAssertEqual(result.standardOutput, "1\n2\n")
        XCTAssertEqual(result.terminationStatus, 0)
        let request = server.waitForRequest()
        XCTAssertTrue(request.contains(#""list-workspaces""#), "server should receive the args: \(request)")
    }

    /// The server keeps the connection open after answering, so the runner
    /// must detect completion by parsing, including answers split across
    /// several writes.
    func testAssemblesChunkedAnswer() throws {
        let server = try MiniSocketServer(
            respondChunks: [#"{"exitCode":0,"stdout":"he"#, #"llo","stderr":""}"#]
        )
        let runner = AeroSpaceSocketRunner(socketPath: server.path, fallback: FailingRunner())

        let result = try runner.run("/usr/bin/aerospace", arguments: ["list-workspaces"])

        XCTAssertEqual(result.standardOutput, "hello")
    }

    func testNonZeroExitCodeThrowsInsteadOfFallingBack() throws {
        let server = try MiniSocketServer(
            respond: #"{"exitCode":1,"stdout":"","stderr":"no focused window"}"#
        )
        let runner = AeroSpaceSocketRunner(socketPath: server.path, fallback: FailingRunner())

        XCTAssertThrowsError(try runner.run("/usr/bin/aerospace", arguments: ["list-windows", "--focused"])) { error in
            guard case let ProcessRunnerError.nonZeroExit(_, _, result) = error else {
                return XCTFail("Expected nonZeroExit, got \(error)")
            }
            XCTAssertEqual(result.standardError, "no focused window")
        }
    }

    func testFallsBackWhenSocketIsMissing() throws {
        let fallback = RecordingRunner(result: ProcessResult(
            standardOutput: "from cli",
            standardError: "",
            terminationStatus: 0
        ))
        let runner = AeroSpaceSocketRunner(socketPath: "/tmp/aerokit-test-no-such.sock", fallback: fallback)

        let result = try runner.run("/usr/bin/aerospace", arguments: ["list-workspaces"])

        XCTAssertEqual(result.standardOutput, "from cli")
        XCTAssertEqual(fallback.calls.withLock { $0 }, [["list-workspaces"]])
    }

    func testFallsBackWhenServerClosesWithoutAnswering() throws {
        let server = try MiniSocketServer(respondChunks: [])
        let fallback = RecordingRunner(result: ProcessResult(
            standardOutput: "from cli",
            standardError: "",
            terminationStatus: 0
        ))
        let runner = AeroSpaceSocketRunner(socketPath: server.path, fallback: fallback)

        let result = try runner.run("/usr/bin/aerospace", arguments: ["list-workspaces"])

        XCTAssertEqual(result.standardOutput, "from cli")
    }
}

// MARK: - Test doubles

/// One-shot unix-socket server: accepts a single connection, records the
/// request, writes the canned chunks, and keeps the connection open the way
/// the AeroSpace server does (closing only when deallocated).
private final class MiniSocketServer: @unchecked Sendable {
    let path: String
    private let listenFD: Int32
    private var request = Data()
    private let served = DispatchSemaphore(value: 0)

    convenience init(respond: String) throws {
        try self.init(respondChunks: [respond])
    }

    init(respondChunks: [String]) throws {
        path = "/tmp/aerokit-test-\(UUID().uuidString.prefix(8)).sock"
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.baseAddress?.copyMemory(from: bytes, byteCount: bytes.count)
        }
        let bound = withUnsafePointer(to: address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listenFD, 1) == 0 else {
            throw NSError(domain: "MiniSocketServer", code: Int(errno))
        }

        let acceptFD = listenFD
        DispatchQueue.global().async { [weak self] in
            let client = accept(acceptFD, nil, nil)
            guard client >= 0 else {
                return
            }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(client, &buffer, buffer.count)
            if count > 0 {
                self?.request.append(buffer, count: count)
            }
            for chunk in respondChunks {
                _ = chunk.withCString { write(client, $0, strlen($0)) }
                // Let distinct chunks land as distinct reads.
                usleep(20000)
            }
            self?.served.signal()
            if respondChunks.isEmpty {
                close(client)
            } else {
                // Mirror the real server: connection stays open after the
                // answer; the runner must not wait for EOF.
                usleep(500_000)
                close(client)
            }
        }
    }

    func waitForRequest() -> String {
        served.wait()
        return String(data: request, encoding: .utf8) ?? ""
    }

    deinit {
        close(listenFD)
        unlink(path)
    }
}

private struct FailingRunner: CommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        throw ProcessRunnerError.launchFailed("fallback must not be used")
    }
}

private final class RecordingRunner: CommandRunning, @unchecked Sendable {
    let calls = NSRecursiveLock.withLockedValue([[String]]())
    private let result: ProcessResult

    init(result: ProcessResult) {
        self.result = result
    }

    func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        calls.withLock { $0.append(arguments) }
        return result
    }
}

/// Minimal locked-box helper so the recording runner is Sendable.
private extension NSRecursiveLock {
    final class LockedValue<Value>: @unchecked Sendable {
        private let lock = NSRecursiveLock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func withLock<T>(_ body: (inout Value) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }

    static func withLockedValue<Value>(_ value: Value) -> LockedValue<Value> {
        LockedValue(value)
    }
}
