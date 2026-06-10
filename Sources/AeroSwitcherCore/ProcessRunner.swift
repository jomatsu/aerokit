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
        }
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> ProcessResult
}

public struct ProcessRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        let executableURL = try resolveExecutable(executable)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let result = ProcessResult(
            standardOutput: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            standardError: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus
        )

        guard result.succeeded else {
            throw ProcessRunnerError.nonZeroExit(executable: executableURL.path, arguments: arguments, result: result)
        }

        return result
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

        do {
            try lookup.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        lookup.waitUntilExit()
        guard lookup.terminationStatus == 0 else {
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
