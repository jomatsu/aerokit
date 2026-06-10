import XCTest
@testable import AeroSwitcherCore

final class ProcessRunnerTests: XCTestCase {
    func testRunCapturesStandardOutput() throws {
        let result = try ProcessRunner().run("/bin/echo", arguments: ["hello"])

        XCTAssertEqual(result.standardOutput, "hello\n")
        XCTAssertEqual(result.terminationStatus, 0)
    }

    func testNonZeroExitThrows() {
        XCTAssertThrowsError(try ProcessRunner().run("/usr/bin/false", arguments: [])) { error in
            guard case ProcessRunnerError.nonZeroExit = error else {
                return XCTFail("Expected nonZeroExit, got \(error)")
            }
        }
    }

    func testHungProcessIsKilledAfterTimeout() {
        let runner = ProcessRunner(timeout: 0.2)
        let started = Date()

        XCTAssertThrowsError(try runner.run("/bin/sleep", arguments: ["30"])) { error in
            guard case ProcessRunnerError.timedOut = error else {
                return XCTFail("Expected timedOut, got \(error)")
            }
        }

        // Well under the 30s sleep: proves the process was killed, not waited out.
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testMissingExecutableThrows() {
        XCTAssertThrowsError(try ProcessRunner().run("/nonexistent/binary", arguments: [])) { error in
            guard case ProcessRunnerError.executableNotFound = error else {
                return XCTFail("Expected executableNotFound, got \(error)")
            }
        }
    }
}
