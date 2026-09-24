import XCTest
@testable import AeroKitCore

final class ScreenCaptureLifetimeTests: XCTestCase {
    func testStopRejectsFurtherCaptures() async {
        let lifetime = ScreenCaptureLifetime()
        lifetime.stop()
        XCTAssertFalse(lifetime.begin())
        await lifetime.waitUntilIdle()
        XCTAssertFalse(lifetime.begin())
    }

    func testShutdownWaitsForEveryInFlightCapture() async {
        let lifetime = ScreenCaptureLifetime()
        XCTAssertTrue(lifetime.begin())
        XCTAssertTrue(lifetime.begin())
        lifetime.stop()
        let drained = expectation(description: "All capture requests finished")
        let waiting = expectation(description: "Shutdown started waiting")
        let finished = CallCounter()
        let waiter = Task {
            waiting.fulfill()
            await lifetime.waitUntilIdle()
            finished.increment()
            drained.fulfill()
        }
        await fulfillment(of: [waiting], timeout: 1)
        lifetime.end()
        XCTAssertFalse(lifetime.begin())
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(finished.count, 0, "The second capture still owns an OS request")
        lifetime.end()
        await fulfillment(of: [drained], timeout: 1)
        await waiter.value
    }

    func testConcurrentCapturesAndShutdown() async {
        let lifetime = ScreenCaptureLifetime()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    if lifetime.begin() {
                        await Task.yield()
                        lifetime.end()
                    }
                }
            }
            group.addTask {
                lifetime.stop()
                await lifetime.waitUntilIdle()
            }
        }
        XCTAssertFalse(lifetime.begin())
        await lifetime.waitUntilIdle()
    }
}
