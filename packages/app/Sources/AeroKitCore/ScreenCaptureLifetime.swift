import Foundation

/// Keeps the process alive until submitted WindowServer/replayd requests finish.
/// State is shared by synchronous CoreGraphics and asynchronous ScreenCaptureKit
/// calls, and every access is protected by the lock.
final class ScreenCaptureLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var isStopping = false
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func begin() -> Bool {
        lock.withLock {
            guard !isStopping else { return false }
            active += 1
            return true
        }
    }

    func end() {
        let completed = lock.withLock {
            active -= 1
            guard active == 0 else { return [CheckedContinuation<Void, Never>]() }
            let completed = waiters
            waiters.removeAll()
            return completed
        }
        for waiter in completed {
            waiter.resume()
        }
    }

    func stop() {
        lock.withLock { isStopping = true }
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if active == 0 {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }
}
