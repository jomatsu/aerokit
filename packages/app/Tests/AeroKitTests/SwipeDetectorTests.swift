import XCTest
@testable import AeroKitCore

final class SwipeDetectorTests: XCTestCase {
    private var detector: SwipeDetector!

    override func setUp() {
        super.setUp()
        // A 100×100 mm pad makes normalized units read directly as
        // millimeters ×100: one committed step is 35 mm, i.e. 0.35 of
        // travel, and a velocity of 1.0 is 100 mm/s.
        detector = SwipeDetector(padWidthMM: 100, padHeightMM: 100)
    }

    private func frame(
        fingers: [(x: Float, y: Float)],
        state: Int32 = 4,
        velocity: (x: Float, y: Float) = (0, 0)
    ) -> [SwipeEvent] {
        let touches = fingers.enumerated().map { index, finger in
            MTTouch(
                frame: 0,
                timestamp: 0,
                identifier: Int32(index + 1),
                state: state,
                fingerID: 0,
                handID: 0,
                normalized: .init(
                    position: .init(horizontal: finger.x, vertical: finger.y),
                    velocity: .init(horizontal: velocity.x, vertical: velocity.y)
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

    /// Compares event sequences with float tolerance on progress values.
    private func assertEvents(
        _ actual: [SwipeEvent],
        _ expected: [SwipeEvent],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, "\(actual) vs \(expected)", file: file, line: line)
        for (event, expectation) in zip(actual, expected) {
            switch (event, expectation) {
            case let (.began(axis), .began(expectedAxis)):
                XCTAssertEqual(axis, expectedAxis, file: file, line: line)
            case let (.moved(axis, progress), .moved(expectedAxis, expectedProgress)):
                XCTAssertEqual(axis, expectedAxis, file: file, line: line)
                XCTAssertEqual(progress, expectedProgress, accuracy: 0.001, file: file, line: line)
            case let (.ended(axis, steps), .ended(expectedAxis, expectedSteps)):
                XCTAssertEqual(axis, expectedAxis, file: file, line: line)
                XCTAssertEqual(steps, expectedSteps, file: file, line: line)
            default:
                XCTFail("\(event) does not match \(expectation)", file: file, line: line)
            }
        }
    }

    private func threeFingers(atY height: Float) -> [(x: Float, y: Float)] {
        [(0.3, height), (0.5, height), (0.7, height)]
    }

    private func threeFingers(atX center: Float) -> [(x: Float, y: Float)] {
        [(center - 0.2, 0.5), (center, 0.5), (center + 0.2, 0.5)]
    }

    func testSlowSwipeUpCommitsAtRelease() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.475)),
            [.began(.vertical), .moved(.vertical, progress: 0.5)]
        )
        assertEvents(frame(fingers: threeFingers(atY: 0.65)), [.moved(.vertical, progress: 1.0)])
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testLongSwipeStillCommitsOneStep() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.15)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.5)),
            [.began(.vertical), .moved(.vertical, progress: 1.0)]
        )
        // Two steps of travel: progress keeps reporting the full distance
        // (the HUD rubber-bands it), but one gesture commits one step.
        assertEvents(frame(fingers: threeFingers(atY: 0.85)), [.moved(.vertical, progress: 2.0)])
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testSwipeDownCommitsNegativeSteps() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.7)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.35)),
            [.began(.vertical), .moved(.vertical, progress: -1.0)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: -1)])
    }

    func testHorizontalSwipesCommitSignedSteps() {
        XCTAssertEqual(frame(fingers: threeFingers(atX: 0.3)), [])
        assertEvents(
            frame(fingers: threeFingers(atX: 0.65)),
            [.began(.horizontal), .moved(.horizontal, progress: 1.0)]
        )
        assertEvents(frame(fingers: []), [.ended(.horizontal, steps: 1)])

        XCTAssertEqual(frame(fingers: threeFingers(atX: 0.65)), [])
        assertEvents(
            frame(fingers: threeFingers(atX: 0.3)),
            [.began(.horizontal), .moved(.horizontal, progress: -1.0)]
        )
        assertEvents(frame(fingers: []), [.ended(.horizontal, steps: -1)])
    }

    func testPullingBackBeforeReleaseCancels() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.65)),
            [.began(.vertical), .moved(.vertical, progress: 1.0)]
        )
        // The fingers return almost to where they started…
        assertEvents(frame(fingers: threeFingers(atY: 0.37)), [.moved(.vertical, progress: 0.2)])
        // …so lifting commits nothing.
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 0)])
    }

    func testShortSlowMovementCancelsAtRelease() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // Less than half a step of slow travel commits nothing.
        assertEvents(
            frame(fingers: threeFingers(atY: 0.44)),
            [.began(.vertical), .moved(.vertical, progress: 0.4)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 0)])
    }

    func testSlowSwipePastHalfAStepCommitsIt() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.51)),
            [.began(.vertical), .moved(.vertical, progress: 0.6)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testFastFlickCommitsFromAShortDistance() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // Only 8 mm of travel, but still moving upward at 250 mm/s at
        // release: the flick completes the step it was headed for.
        assertEvents(
            frame(fingers: threeFingers(atY: 0.38), velocity: (0, 2.5)),
            [.began(.vertical), .moved(.vertical, progress: 0.2286)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testResidualDriftDoesNotAddAStep() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // A deliberate one-step drag released while still creeping at
        // 60 mm/s must stay one step.
        assertEvents(
            frame(fingers: threeFingers(atY: 0.65), velocity: (0, 0.6)),
            [.began(.vertical), .moved(.vertical, progress: 1.0)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testFlickNeverCommitsPastTheNextStep() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // 21 mm of travel — past half a step — released still moving fast:
        // the flick completes the step in progress, never the one beyond.
        assertEvents(
            frame(fingers: threeFingers(atY: 0.51), velocity: (0, 4.0)),
            [.began(.vertical), .moved(.vertical, progress: 0.6)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testFlickAtAStepBoundaryDoesNotLeakAnExtraStep() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // Exactly one step of travel, still moving fast at release.
        assertEvents(
            frame(fingers: threeFingers(atY: 0.65), velocity: (0, 4.0)),
            [.began(.vertical), .moved(.vertical, progress: 1.0)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testFlickOnALongSwipeStillCommitsOneStep() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.15)), [])
        // 1.4 steps of travel released as a flick: neither the distance nor
        // the velocity can push a single gesture past one step.
        assertEvents(
            frame(fingers: threeFingers(atY: 0.64), velocity: (0, 4.0)),
            [.began(.vertical), .moved(.vertical, progress: 1.4)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testSmallBackwardDriftDoesNotCancelAPastHalfwayRelease() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // Past half a step with a light backward creep on the final frame —
        // lift-off noise, not a throw-back — the nearest step commits, as
        // the highlight under the fingers shows.
        assertEvents(
            frame(fingers: threeFingers(atY: 0.51), velocity: (0, -0.6)),
            [.began(.vertical), .moved(.vertical, progress: 0.6)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testBackwardVelocityCannotCancelACompletedStep() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // A full step of travel with backward velocity at release: the
        // boundary was reached, so the step stays committed.
        assertEvents(
            frame(fingers: threeFingers(atY: 0.65), velocity: (0, -2.5)),
            [.began(.vertical), .moved(.vertical, progress: 1.0)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testOpposingVelocityPullsTheCommitBack() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // The fingers travelled past half a step but are snapping back
        // downward at release.
        assertEvents(
            frame(fingers: threeFingers(atY: 0.51), velocity: (0, -2.5)),
            [.began(.vertical), .moved(.vertical, progress: 0.6)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 0)])
    }

    func testLiftingFingersArmsANewGesture() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.65)),
            [.began(.vertical), .moved(.vertical, progress: 1.0)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])

        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.65)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.3)),
            [.began(.vertical), .moved(.vertical, progress: -1.0)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: -1)])
    }

    func testTwoAndFourFingersProduceNoEvents() {
        XCTAssertEqual(frame(fingers: [(0.4, 0.3), (0.6, 0.3)]), [])
        XCTAssertEqual(frame(fingers: [(0.4, 0.6), (0.6, 0.6)]), [])

        let four: ([Float]) -> [(x: Float, y: Float)] = { ys in
            zip([0.2, 0.4, 0.6, 0.8] as [Float], ys).map { ($0, $1) }
        }
        XCTAssertEqual(frame(fingers: four([0.3, 0.3, 0.3, 0.3])), [])
        XCTAssertEqual(frame(fingers: four([0.6, 0.6, 0.6, 0.6])), [])
    }

    func testHoveringFingersAreIgnored() {
        // State 2 is hover-in-range: the fingers are not on the pad.
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3), state: 2), [])
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.6), state: 2), [])
    }

    func testDominantVerticalAxisWinsOverHorizontalDrift() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // Both axes moved, the vertical one decisively further.
        assertEvents(
            frame(fingers: [(0.38, 0.5), (0.58, 0.5), (0.78, 0.5)]),
            [.began(.vertical), .moved(.vertical, progress: 0.5714)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testAxisStaysLockedAfterBeginning() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.4)),
            [.began(.vertical), .moved(.vertical, progress: 0.2857)]
        )
        // A late horizontal drift larger than the vertical travel still
        // reports along the locked vertical axis.
        assertEvents(
            frame(fingers: [(0.45, 0.4), (0.65, 0.4), (0.85, 0.4)]),
            [.moved(.vertical, progress: 0.2857)]
        )
    }

    func testBriefFingerDropoutKeepsTheGesture() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        // One contact flickers out for a single frame.
        XCTAssertEqual(frame(fingers: [(0.3, 0.4), (0.5, 0.4)]), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.65)),
            [.began(.vertical), .moved(.vertical, progress: 1.0)]
        )
        assertEvents(frame(fingers: []), [.ended(.vertical, steps: 1)])
    }

    func testProlongedDropoutEndsTheGesture() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.55)),
            [.began(.vertical), .moved(.vertical, progress: 0.7143)]
        )
        XCTAssertEqual(frame(fingers: [(0.3, 0.55), (0.5, 0.55)]), [])
        XCTAssertEqual(frame(fingers: [(0.3, 0.55), (0.5, 0.55)]), [])
        // The grace window expires: the gesture ends as a release.
        assertEvents(frame(fingers: [(0.3, 0.55), (0.5, 0.55)]), [.ended(.vertical, steps: 1)])
    }

    func testFourthFingerCancelsUntilAllFingersLift() {
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.45)),
            [.began(.vertical), .moved(.vertical, progress: 0.4286)]
        )
        // A fourth finger lands: the in-flight gesture cancels…
        assertEvents(
            frame(fingers: [(0.2, 0.45), (0.4, 0.45), (0.6, 0.45), (0.8, 0.45)]),
            [.ended(.vertical, steps: 0)]
        )
        // …and three fingers moving again stay dead until a full lift.
        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.6)), [])
        XCTAssertEqual(frame(fingers: []), [])

        XCTAssertEqual(frame(fingers: threeFingers(atY: 0.3)), [])
        assertEvents(
            frame(fingers: threeFingers(atY: 0.65)),
            [.began(.vertical), .moved(.vertical, progress: 1.0)]
        )
    }

    func testSplayingFingersNeverBegin() {
        XCTAssertEqual(frame(fingers: [(0.3, 0.3), (0.5, 0.3), (0.7, 0.3)]), [])
        // Two fingers slide up while one slides down: the centroid moves
        // but the fingers disagree, so no gesture begins.
        XCTAssertEqual(frame(fingers: [(0.3, 0.6), (0.5, 0.6), (0.7, 0.25)]), [])
        XCTAssertEqual(frame(fingers: [(0.3, 0.8), (0.5, 0.8), (0.7, 0.27)]), [])
        XCTAssertEqual(frame(fingers: []), [])
    }
}
