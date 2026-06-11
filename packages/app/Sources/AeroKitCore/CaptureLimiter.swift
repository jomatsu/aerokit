import Foundation

/// Process-wide cap on concurrent window captures. More than ~8 simultaneous
/// CGWindowListCreateImage calls contend on the app's WindowServer connection
/// and start returning nil, so every capture pipeline (snapshot refresh,
/// exposé previews) takes a slot here before touching the window server.
public actor CaptureLimiter {
    public static let shared = CaptureLimiter(limit: 8)

    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) {
        self.limit = limit
    }

    public func withSlot<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            // Hand the slot straight to the next waiter; `active` stays put.
            waiters.removeFirst().resume()
        }
    }
}
