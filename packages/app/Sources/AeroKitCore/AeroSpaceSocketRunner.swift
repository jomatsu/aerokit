import Darwin
import Foundation

/// Runs AeroSpace commands over the server's unix socket directly, skipping
/// the `aerospace` CLI process spawn — ~1-4ms per call instead of ~30-80ms,
/// which is what makes a multi-call presentation feel instant.
///
/// The wire protocol is the CLI's own (one JSON `ClientRequest` per request,
/// one JSON `ServerAnswer` back) but it is not a public API
/// (nikitabobko/AeroSpace#1513), so every transport-level failure — socket
/// missing, protocol drift, truncated answer — falls back to spawning the
/// real CLI binary. A non-zero exit code in the server's answer is a real
/// answer, not a transport failure: it throws like ProcessRunner would
/// instead of pointlessly retrying through the binary.
public struct AeroSpaceSocketRunner: CommandRunning {
    private struct ClientRequest: Encodable {
        var args: [String]
        var stdin = ""
    }

    private struct ServerAnswer: Decodable {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private enum TransportError: Error {
        case socketUnavailable
        case writeFailed
        case connectionClosed
    }

    /// Where AeroSpace listens: `/tmp/bobko.aerospace-<user>.sock`.
    public static func defaultSocketPath() -> String {
        "/tmp/bobko.aerospace-\(NSUserName()).sock"
    }

    private let socketPath: String
    private let fallback: any CommandRunning
    /// Socket send/receive timeout; a wedged server must not pin the
    /// caller's thread, mirroring ProcessRunner's kill-after-timeout.
    private let timeout: TimeInterval

    public init(
        socketPath: String = AeroSpaceSocketRunner.defaultSocketPath(),
        fallback: any CommandRunning = ProcessRunner(),
        timeout: TimeInterval = 10
    ) {
        self.socketPath = socketPath
        self.fallback = fallback
        self.timeout = timeout
    }

    public func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        let answer: ServerAnswer
        do {
            answer = try request(arguments)
        } catch {
            return try fallback.run(executable, arguments: arguments)
        }

        let result = ProcessResult(
            standardOutput: answer.stdout,
            standardError: answer.stderr,
            terminationStatus: answer.exitCode
        )
        guard result.succeeded else {
            throw ProcessRunnerError.nonZeroExit(executable: executable, arguments: arguments, result: result)
        }
        return result
    }

    private func request(_ arguments: [String]) throws -> ServerAnswer {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw TransportError.socketUnavailable
        }
        defer { close(fd) }
        applyTimeout(fd)

        try connectToServer(fd)
        try send(JSONEncoder().encode(ClientRequest(args: arguments)), to: fd)
        return try readAnswer(from: fd)
    }

    private func applyTimeout(_ fd: Int32) {
        var limit = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32(timeout.truncatingRemainder(dividingBy: 1) * 1_000_000)
        )
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, size)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, size)
    }

    private func connectToServer(_ fd: Int32) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8)
        // sun_path is a fixed 104-byte buffer needing a trailing NUL.
        guard path.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw TransportError.socketUnavailable
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.baseAddress?.copyMemory(from: path, byteCount: path.count)
        }
        let connected = withUnsafePointer(to: address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw TransportError.socketUnavailable
        }
    }

    private func send(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else {
                throw TransportError.writeFailed
            }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base + offset, raw.count - offset)
                if written > 0 {
                    offset += written
                } else if errno != EINTR {
                    throw TransportError.writeFailed
                }
            }
        }
    }

    /// The server writes exactly one JSON answer and keeps the connection
    /// open, so completion is "the bytes parse", not EOF; large answers
    /// (long window lists) arrive in several reads.
    private func readAnswer(from fd: Int32) throws -> ServerAnswer {
        let decoder = JSONDecoder()
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                received.append(buffer, count: count)
                if let answer = try? decoder.decode(ServerAnswer.self, from: received) {
                    return answer
                }
            } else if count == 0 || errno != EINTR {
                // 0 is the server closing before a parseable answer; a
                // signal interruption just reads again.
                throw TransportError.connectionClosed
            }
        }
    }
}
