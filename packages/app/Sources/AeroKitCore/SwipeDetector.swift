import Foundation

/// Turns raw contact frames into three-finger gesture events, modeled on how
/// macOS's own gesture engine behaves: thresholds are physical millimeters
/// so every pad size feels alike, the swipe axis locks early in the gesture,
/// all three fingers must move together before it engages, and at release a
/// fast flick commits from a shorter distance than a slow drag. Runs on the
/// MultitouchSupport callback thread; the lock keeps frames from concurrent
/// callbacks from interleaving.
final class SwipeDetector: @unchecked Sendable {
    /// Travel after which the swipe axis locks to the dominant direction.
    private static let axisLockDistanceMM: Float = 3
    /// How decisively one axis must beat the other to lock; until then a
    /// diagonal wobble keeps the gesture undecided rather than guessing.
    private static let axisDominanceRatio: Float = 1.2
    /// Seconds of post-release coasting credited to the commit: the
    /// fingers' release velocity projects this far ahead, so a flick
    /// commits the step it was clearly headed for while the residual drift
    /// of a careful drag barely moves the projection.
    private static let momentumProjectionSeconds: Float = 0.15
    /// Momentum may add at most one step beyond the travelled distance, so
    /// a violent flick cannot fly past what the fingers actually did.
    private static let momentumStepCap: Float = 1.0
    /// Every finger must itself travel this far in the swipe direction
    /// before the axis can lock; splaying or pinching fingers can move the
    /// centroid without anyone having swiped.
    private static let perFingerDistanceMM: Float = 2
    /// Consecutive frames with fewer than three fingers tolerated
    /// mid-gesture; light contacts flicker in and out between frames.
    private static let dropoutGraceFrames = 2

    private enum Phase {
        case idle
        /// Three fingers are down; their travel has not picked an axis yet.
        case tracking
        case locked(SwipeAxis)
        /// A fourth finger appeared. Staying cancelled until every finger
        /// lifts keeps a partially raised four-finger gesture from swiping.
        case cancelled
    }

    private let padWidthMM: Float
    private let padHeightMM: Float
    /// Travel worth one committed step: progress 1.0. Commits round to the
    /// nearest step, so a slow swipe crosses into a step at half this
    /// distance — the point where a progress UI already shows that step.
    /// Long enough by default that a multi-step drag has a comfortable
    /// release window around every step; user-tunable via settings.
    private let stepDistanceMM: Float
    private let lock = NSLock()
    private var phase = Phase.idle
    private var graceLeft = 0
    /// Where each finger touched down, keyed by the hardware's contact
    /// identifier; measuring every finger from its own start point keeps a
    /// landing or lifting finger from jerking a shared average around.
    private var baselines: [Int32: (x: Float, y: Float)] = [:]
    /// Last readings while three fingers were down, used to decide the
    /// outcome at release; speed is mm/s along the locked axis.
    private var lastProgress: Float = 0
    private var lastSpeed: Float = 0

    /// Built-in MacBook pad dimensions, the fallback when the private
    /// surface-dimensions call is unavailable.
    static let fallbackPadSizeMM: (width: Float, height: Float) = (120, 80)

    init(
        padWidthMM: Float = SwipeDetector.fallbackPadSizeMM.width,
        padHeightMM: Float = SwipeDetector.fallbackPadSizeMM.height,
        stepDistanceMM: Float = TrackpadSwipeMonitor.defaultStepDistanceMM
    ) {
        self.padWidthMM = padWidthMM
        self.padHeightMM = padHeightMM
        self.stepDistanceMM = stepDistanceMM
    }

    // A single-pass gesture state machine: the phase, per-finger baselines,
    // and dropout grace are threaded through one traversal of the frame, so
    // splitting it would scatter that shared state across helpers for no real
    // clarity gain.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func process(touches: UnsafePointer<MTTouch>?, count: Int) -> [SwipeEvent] {
        lock.lock()
        defer { lock.unlock() }

        var touching = 0
        if let touches {
            for index in 0 ..< count where touches[index].isTouching {
                touching += 1
            }
        }

        if touching == 0 {
            return endGesture()
        }
        if touching > 3 {
            // The gesture is something else; report a cancel if one was in
            // flight so consumers can settle their UI.
            let events = cancelEvents()
            phase = .cancelled
            baselines = [:]
            return events
        }

        // Resolve every frame that needs no per-finger data before
        // materializing it, so ordinary one- and two-finger pointer use —
        // the vast majority of the ~120 Hz contact frames — allocates
        // nothing here.
        switch phase {
        case .cancelled:
            return []
        case .idle:
            guard touching == 3 else {
                return []
            }
        case .tracking, .locked:
            if touching < 3 {
                graceLeft -= 1
                if graceLeft < 0 {
                    return endGesture()
                }
                return []
            }
        }

        // Exactly three fingers from here on.
        // A positional record that lives only within this pass and never
        // escapes, so a tuple stays clearer here than a named struct.
        // swiftlint:disable:next large_tuple
        var fingers: [(id: Int32, x: Float, y: Float, vx: Float, vy: Float)] = []
        fingers.reserveCapacity(3)
        if let touches {
            for index in 0 ..< count where touches[index].isTouching {
                let touch = touches[index]
                fingers.append((
                    id: touch.identifier,
                    x: touch.normalized.position.horizontal,
                    y: touch.normalized.position.vertical,
                    vx: touch.normalized.velocity.horizontal,
                    vy: touch.normalized.velocity.vertical
                ))
            }
        }

        if case .idle = phase {
            phase = .tracking
            graceLeft = Self.dropoutGraceFrames
            baselines = .init(uniqueKeysWithValues: fingers.map { ($0.id, (x: $0.x, y: $0.y)) })
            lastProgress = 0
            lastSpeed = 0
            return []
        }
        graceLeft = Self.dropoutGraceFrames

        // A finger that lands mid-gesture measures from where it landed.
        for finger in fingers where baselines[finger.id] == nil {
            baselines[finger.id] = (x: finger.x, y: finger.y)
        }

        // Per-finger displacement in millimeters from each finger's own
        // touch-down point. Normalized y grows toward the top edge of the
        // pad, so positive vertical displacement means "up" already.
        let displacements = fingers.compactMap { finger -> (x: Float, y: Float)? in
            guard let baseline = baselines[finger.id] else {
                return nil
            }
            return (
                x: (finger.x - baseline.x) * padWidthMM,
                y: (finger.y - baseline.y) * padHeightMM
            )
        }
        let centroidX = displacements.reduce(0) { $0 + $1.x } / 3
        let centroidY = displacements.reduce(0) { $0 + $1.y } / 3

        var events: [SwipeEvent] = []
        if case .tracking = phase {
            let absX = abs(centroidX)
            let absY = abs(centroidY)
            guard max(absX, absY) >= Self.axisLockDistanceMM else {
                return []
            }
            let axis: SwipeAxis
            if absX > absY * Self.axisDominanceRatio {
                axis = .horizontal
            } else if absY > absX * Self.axisDominanceRatio {
                axis = .vertical
            } else {
                return []
            }
            let centroid = axis == .horizontal ? centroidX : centroidY
            let unanimous = displacements.allSatisfy { displacement in
                let along = axis == .horizontal ? displacement.x : displacement.y
                return along * centroid > 0 && abs(along) >= Self.perFingerDistanceMM
            }
            guard unanimous else {
                return []
            }
            phase = .locked(axis)
            events.append(.began(axis))
        }
        guard case let .locked(axis) = phase else {
            return []
        }

        let centroid = axis == .horizontal ? centroidX : centroidY
        // Velocity comes pre-smoothed from the framework in normalized
        // units per second; keep the last reading for the release decision.
        lastSpeed = fingers.reduce(Float(0)) { sum, finger in
            sum + (axis == .horizontal ? finger.vx * padWidthMM : finger.vy * padHeightMM)
        } / 3
        lastProgress = centroid / stepDistanceMM
        events.append(.moved(axis, progress: lastProgress))
        return events
    }

    /// Every finger lifted (or stayed below three past the grace window):
    /// decide what the gesture committed and reset for the next touch-down.
    private func endGesture() -> [SwipeEvent] {
        defer {
            phase = .idle
            baselines = [:]
            lastProgress = 0
            lastSpeed = 0
        }
        guard case let .locked(axis) = phase else {
            return []
        }
        return [.ended(axis, steps: steps(progress: lastProgress, speed: lastSpeed))]
    }

    private func cancelEvents() -> [SwipeEvent] {
        guard case let .locked(axis) = phase else {
            return []
        }
        return [.ended(axis, steps: 0)]
    }

    private func steps(progress: Float, speed: Float) -> Int {
        // Project the release velocity ahead like scroll-view deceleration:
        // momentum carries a flick into the step it was headed for, and an
        // opposing throw-back naturally subtracts toward a cancel.
        let momentum = speed * Self.momentumProjectionSeconds / stepDistanceMM
        let projected = progress + max(-Self.momentumStepCap, min(Self.momentumStepCap, momentum))
        // Round to nearest so the gesture commits whatever step its
        // projection is closest to — what a progress UI shows under the
        // fingers at release. The epsilon keeps float noise from flipping
        // exact-half-way releases toward zero.
        let epsilon: Float = projected >= 0 ? 0.0001 : -0.0001
        return Int((projected + epsilon).rounded())
    }
}
