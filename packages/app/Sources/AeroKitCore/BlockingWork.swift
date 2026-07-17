import Foundation

/// Runs a blocking AeroSpace/CLI round trip on a dedicated GCD queue and
/// suspends the caller until it returns, keeping the work off Swift
/// concurrency's cooperative pool.
///
/// Every AeroSpace round trip can wedge: `ProcessRunner` blocks on a semaphore
/// for up to 10s before killing a hung CLI, and `AeroSpaceSocketRunner` blocks
/// on socket timeouts for up to 10s before falling back to the CLI for another
/// 10s. The cooperative pool has only as many threads as the machine has
/// cores, so a `Task.detached` running one of these stalls pins a cooperative
/// thread for the whole ~20s — a handful of wedged calls can leave the app's
/// other Tasks with no thread to run on. Hopping to a private concurrent
/// `DispatchQueue` moves the stalls onto GCD's own thread pool, which grows
/// elastically: a blocked thread there is GCD's problem to schedule around,
/// not a seat the entire app's async work is contending for.
public enum BlockingWork {
    /// Where the blocking calls land instead of the cooperative pool.
    /// Concurrent so independent round trips (e.g. the exposé's deliberately
    /// overlapped focused-window and drop-bar queries) still run in parallel.
    private static let queue = DispatchQueue(
        label: "com.nasubikun.aerokit.blocking-work",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    /// Throwing variant: a failed round trip rethrows to the caller.
    public static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result(catching: work))
            }
        }
    }
}
