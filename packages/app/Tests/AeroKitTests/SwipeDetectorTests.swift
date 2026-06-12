import XCTest
@testable import AeroKitCore

final class SwipeDetectorTests: XCTestCase {
    private var detector: SwipeDetector!

    override func setUp() {
        super.setUp()
        detector = SwipeDetector()
    }

    private func frame(fingers: [(x: Float, y: Float)], state: Int32 = 4) -> TrackpadSwipeMonitor.Direction? {
        let touches = fingers.map { finger in
            MTTouch(
                frame: 0,
                timestamp: 0,
                identifier: 0,
                state: state,
                fingerID: 0,
                handID: 0,
                normalized: .init(
                    position: .init(horizontal: finger.x, vertical: finger.y),
                    velocity: .init(horizontal: 0, vertical: 0)
                ),
                total: 0,
                pressure: 0,
                angle: 0,
                majorAxis: 0,
                minorAxis: 0,
                absolute: .init(
                    position: .init(horizontal: 0, vertical: 0),
                    velocity: .init(horizontal: 0, vertical: 0)
                ),
                field14: 0,
                field15: 0,
                density: 0
            )
        }
        return touches.withUnsafeBufferPointer { buffer in
            detector.process(touches: buffer.baseAddress, count: buffer.count)
        }
    }

    private func threeFingers(atY height: Float) -> [(x: Float, y: Float)] {
        [(0.3, height), (0.5, height), (0.7, height)]
    }

    func testThreeFingerSwipeUpFiresOnce() {
        XCTAssertNil(frame(fingers: threeFingers(atY: 0.3)))
        XCTAssertNil(frame(fingers: threeFingers(atY: 0.35)))
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.5)), .up)
        // Continuing the same gesture must not fire again.
        XCTAssertNil(frame(fingers: threeFingers(atY: 0.8)))
    }

    func testThreeFingerSwipeDownFires() {
        XCTAssertNil(frame(fingers: threeFingers(atY: 0.7)))
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.5)), .down)
    }

    func testLiftingFingersArmsANewGesture() {
        XCTAssertNil(frame(fingers: threeFingers(atY: 0.3)))
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.5)), .up)

        XCTAssertNil(frame(fingers: []))

        XCTAssertNil(frame(fingers: threeFingers(atY: 0.3)))
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.5)), .up)
    }

    func testTwoAndFourFingersDoNotFire() {
        XCTAssertNil(frame(fingers: [(0.4, 0.3), (0.6, 0.3)]))
        XCTAssertNil(frame(fingers: [(0.4, 0.6), (0.6, 0.6)]))

        let four: ([Float]) -> [(x: Float, y: Float)] = { ys in
            zip([0.2, 0.4, 0.6, 0.8] as [Float], ys).map { ($0, $1) }
        }
        XCTAssertNil(frame(fingers: four([0.3, 0.3, 0.3, 0.3])))
        XCTAssertNil(frame(fingers: four([0.6, 0.6, 0.6, 0.6])))
    }

    func testHoveringFingersAreIgnored() {
        // State 2 is hover-in-range: the fingers are not on the pad.
        XCTAssertNil(frame(fingers: threeFingers(atY: 0.3), state: 2))
        XCTAssertNil(frame(fingers: threeFingers(atY: 0.6), state: 2))
    }

    private func threeFingers(atX center: Float) -> [(x: Float, y: Float)] {
        [(center - 0.2, 0.5), (center, 0.5), (center + 0.2, 0.5)]
    }

    func testThreeFingerSwipeRightFiresOnce() {
        XCTAssertNil(frame(fingers: threeFingers(atX: 0.3)))
        XCTAssertNil(frame(fingers: threeFingers(atX: 0.35)))
        XCTAssertEqual(frame(fingers: threeFingers(atX: 0.5)), .right)
        // Continuing the same gesture must not fire again.
        XCTAssertNil(frame(fingers: threeFingers(atX: 0.7)))
    }

    func testThreeFingerSwipeLeftFires() {
        XCTAssertNil(frame(fingers: threeFingers(atX: 0.6)))
        XCTAssertEqual(frame(fingers: threeFingers(atX: 0.4)), .left)
    }

    func testMostlyHorizontalMovementFiresHorizontally() {
        XCTAssertNil(frame(fingers: [(0.2, 0.5), (0.3, 0.5), (0.4, 0.5)]))
        XCTAssertEqual(frame(fingers: [(0.5, 0.55), (0.6, 0.55), (0.7, 0.55)]), .right)
    }

    func testDominantVerticalAxisWinsOverHorizontalDrift() {
        XCTAssertNil(frame(fingers: threeFingers(atY: 0.3)))
        // Both axes moved, the vertical one further.
        XCTAssertEqual(frame(fingers: [(0.38, 0.5), (0.58, 0.5), (0.78, 0.5)]), .up)
    }
}
