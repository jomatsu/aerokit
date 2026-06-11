import Foundation

public struct ProcessResult: Sendable {
    public var standardOutput: String
    public var standardError: String
    public var terminationStatus: Int32

    public var succeeded: Bool {
        terminationStatus == 0
    }
}

public enum ProcessRunnerError: Error, CustomStringConvertible {
    case executableNotFound(String)
    case launchFailed(String)
    case nonZeroExit(executable: String, arguments: [String], result: ProcessResult)
    case timedOut(executable: String, arguments: [String], timeout: TimeInterval)

    public var description: String {
        switch self {
        case let .executableNotFound(path):
            "Executable not found: \(path)"
        case let .launchFailed(message):
            "Process launch failed: \(message)"
        case let .nonZeroExit(executable, arguments, result):
            """
            \(executable) \(arguments.joined(separator: " ")) \
            exited \(result.terminationStatus): \(result.standardError)
            """
        case let .timedOut(executable, arguments, timeout):
            "\(executable) \(arguments.joined(separator: " ")) timed out after \(Int(timeout))s and was killed"
        }
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> ProcessResult
}

public struct ProcessRunner: CommandRunning {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 10) {
        self.timeout = timeout
    }

    public func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        let executableURL = try resolveExecutable(executable)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        // Drain both pipes while the process runs; waiting first deadlocks once
        // output exceeds the pipe buffer.
        let stdoutReader = PipeReader(stdout)
        let stderrReader = PipeReader(stderr)

        guard waitForExit(process, signaledBy: exited) else {
            throw ProcessRunnerError.timedOut(
                executable: executableURL.path,
                arguments: arguments,
                timeout: timeout
            )
        }

        let result = ProcessResult(
            standardOutput: String(data: stdoutReader.waitForData(), encoding: .utf8) ?? "",
            standardError: String(data: stderrReader.waitForData(), encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus
        )

        guard result.succeeded else {
            throw ProcessRunnerError.nonZeroExit(executable: executableURL.path, arguments: arguments, result: result)
        }

        return result
    }

    /// Returns false when the process outlived `timeout` and had to be
    /// killed; a hung CLI must not pin a thread (and its pipe readers)
    /// forever.
    private func waitForExit(_ process: Process, signaledBy exited: DispatchSemaphore) -> Bool {
        if exited.wait(timeout: .now() + timeout) == .success {
            return true
        }

        process.terminate()
        if exited.wait(timeout: .now() + 2) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            exited.wait()
        }
        return false
    }

    /// @unchecked Sendable: `data` is written once on the background queue;
    /// group.wait() in waitForData() orders that write before the read.
    private final class PipeReader: @unchecked Sendable {
        private var data = Data()
        private let group = DispatchGroup()

        init(_ pipe: Pipe) {
            let handle = pipe.fileHandleForReading
            group.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                data = handle.readDataToEndOfFile()
                group.leave()
            }
        }

        func waitForData() -> Data {
            group.wait()
            return data
        }
    }

    private func resolveExecutable(_ executable: String) throws -> URL {
        if executable.hasPrefix("/") {
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw ProcessRunnerError.executableNotFound(executable)
            }
            return URL(fileURLWithPath: executable)
        }

        let lookup = Process()
        lookup.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        lookup.arguments = ["which", executable]
        let stdout = Pipe()
        lookup.standardOutput = stdout
        lookup.standardError = Pipe()

        let exited = DispatchSemaphore(value: 0)
        lookup.terminationHandler = { _ in exited.signal() }

        do {
            try lookup.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        guard waitForExit(lookup, signaledBy: exited), lookup.terminationStatus == 0 else {
            throw ProcessRunnerError.executableNotFound(executable)
        }

        let path = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else {
            throw ProcessRunnerError.executableNotFound(executable)
        }
        return URL(fileURLWithPath: path)
    }
}
