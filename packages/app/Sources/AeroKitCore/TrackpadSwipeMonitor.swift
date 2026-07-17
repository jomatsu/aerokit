import AppKit
import Darwin
import Foundation

private let log = AppLog(category: "core")

/// Detects three-finger swipes on Apple trackpads through the private
/// MultitouchSupport framework — the only way to observe trackpad touches
/// globally, since NSEvent gesture events only reach the app's own windows.
/// The framework is loaded with dlopen/dlsym so the build carries no
/// link-time dependency on a private framework.
@MainActor
public final class TrackpadSwipeMonitor {
    /// Outcome of a vertical gesture, for consumers with discrete up/down
    /// actions (exposé). Horizontal consumers track SwipeEvent instead.
    public enum Direction: Sendable {
        case up
        case down
    }

    /// Called on the main actor for every gesture lifecycle event, in
    /// order: one `began`, a `moved` per contact frame, one `ended`.
    public var onSwipeEvent: ((SwipeEvent) -> Void)?

    public private(set) var isRunning = false

    /// Single source for the step distance default; preferences and
    /// detectors derive from it.
    public nonisolated static let defaultStepDistanceMM: Float = 35

    /// Finger travel in millimeters worth one committed step; restarting
    /// applies it because each device's detector bakes the value in.
    public var stepDistanceMM = TrackpadSwipeMonitor.defaultStepDistanceMM {
        didSet {
            guard isRunning, oldValue != stepDistanceMM else {
                return
            }
            stop()
            start()
        }
    }

    /// Settings-pane message for a feature whose swipe gesture is enabled
    /// while the shared monitor could not start; nil when there is nothing
    /// to report. Shared so the wording cannot drift between features.
    public static func unavailableMessage(gestureEnabled: Bool, monitorRunning: Bool) -> String? {
        gestureEnabled && !monitorRunning
            ? "Could not access the trackpad for three-finger swipes."
            : nil
    }

    /// Routes the C callback — which cannot capture context — back to the
    /// monitor that registered it and to that device's detector.
    /// Lock-protected because start()/stop() assign on the main actor while
    /// the callback reads on a MultitouchSupport thread. Only one monitor
    /// runs at a time.
    private static let active = ActiveState()

    private final class ActiveState: @unchecked Sendable {
        private let lock = NSLock()
        private weak var monitor: TrackpadSwipeMonitor?
        private var detectors: [UnsafeRawPointer: SwipeDetector] = [:]

        func activate(_ monitor: TrackpadSwipeMonitor, detectors: [UnsafeRawPointer: SwipeDetector]) {
            lock.lock()
            defer { lock.unlock() }
            self.monitor = monitor
            self.detectors = detectors
        }

        func deactivate() {
            lock.lock()
            defer { lock.unlock() }
            monitor = nil
            detectors = [:]
        }

        func lookup(_ device: UnsafeRawPointer?) -> (TrackpadSwipeMonitor, SwipeDetector)? {
            lock.lock()
            defer { lock.unlock() }
            guard let monitor, let device, let detector = detectors[device] else {
                return nil
            }
            return (monitor, detector)
        }
    }

    private var devices: CFArray?
    private var framework: Framework?
    /// Sleep/wake commonly leaves the MultitouchSupport contact callbacks
    /// silently detached — the devices still enumerate but never fire again —
    /// so the monitor re-registers them on `NSWorkspace.didWakeNotification`.
    /// Held here as the balancing counterpart to `stop()`, since the same
    /// instance is started and stopped repeatedly (see `stepDistanceMM`).
    private var wakeObserver: (any NSObjectProtocol)?
    /// The post-wake re-registration is staggered because the trackpad is
    /// often not yet enumerable in the first moments after wake; retained so
    /// an external `stop()` can cancel a retry nobody wants anymore.
    private var restartTask: Task<Void, Never>?

    public init() {}

    /// Returns false when the framework or a multitouch device is
    /// unavailable (no trackpad, or the private API moved).
    @discardableResult
    public func start() -> Bool {
        guard !isRunning else {
            return true
        }
        guard let framework = framework ?? Framework.load() else {
            return false
        }
        self.framework = framework

        guard let list = framework.createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            return false
        }

        devices = list
        var detectors: [UnsafeRawPointer: SwipeDetector] = [:]
        for index in 0 ..< CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else {
                continue
            }
            let reference = MTDeviceRef(mutating: device)
            let pad = framework.padSizeMM(of: reference)
            // One detector per device: each trackpad gets thresholds scaled
            // to its physical size, and frames from a second pad can never
            // corrupt another gesture's baseline.
            detectors[device] = SwipeDetector(
                padWidthMM: pad.width,
                padHeightMM: pad.height,
                stepDistanceMM: stepDistanceMM
            )
            framework.registerCallback(reference, Self.contactCallback)
            framework.startDevice(reference, 0)
        }
        Self.active.activate(self, detectors: detectors)
        isRunning = true
        addWakeObserver()
        return true
    }

    public func stop() {
        // Tear down the wake machinery ahead of the running-state guard: an
        // external stop() (the user disabling the feature) arriving while a
        // post-wake retry is mid-flight must win, or the retry loop would go
        // on to restart a monitor nobody wants running.
        restartTask?.cancel()
        restartTask = nil
        removeWakeObserver()
        guard isRunning, let framework, let devices else {
            return
        }
        for index in 0 ..< CFArrayGetCount(devices) {
            guard let device = CFArrayGetValueAtIndex(devices, index) else {
                continue
            }
            let reference = MTDeviceRef(mutating: device)
            framework.stopDevice(reference)
            framework.unregisterCallback(reference, Self.contactCallback)
        }
        self.devices = nil
        // Dropping the detectors also drops any in-flight gesture state, so
        // the next start() always measures from a fresh baseline.
        Self.active.deactivate()
        isRunning = false
    }

    // MARK: - Sleep/wake recovery

    /// Idempotent so the repeated stop()/start() cycles (e.g. a
    /// `stepDistanceMM` change) never stack duplicate observers.
    private func addWakeObserver() {
        guard wakeObserver == nil else {
            return
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
    }

    private func removeWakeObserver() {
        guard let wakeObserver else {
            return
        }
        NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        self.wakeObserver = nil
    }

    /// stop() drops the stale device registrations and gesture state; the
    /// observer is re-armed at once so a wake whose retries all fail can still
    /// recover on a later wake, and the staggered start() attempts span the
    /// window where the trackpad is not yet enumerable right after wake.
    private func handleWake() {
        guard isRunning else {
            return
        }
        stop()
        addWakeObserver()
        restartTask = Task { @MainActor [weak self] in
            for delay in [Duration.zero, .seconds(1), .seconds(3)] {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
                if Task.isCancelled {
                    return
                }
                guard let self else {
                    return
                }
                if start() {
                    return
                }
            }
            log.error("trackpad swipe monitor did not recover after wake")
        }
    }

    // MARK: - MultitouchSupport bridging

    private typealias MTDeviceRef = UnsafeMutableRawPointer
    /// The touches parameter is really `MTTouch *`; it stays a raw pointer
    /// because @convention(c) cannot mention a Swift-declared struct.
    fileprivate typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32
    ) -> Int32

    /// Delivered on a MultitouchSupport background thread. Dispatching via
    /// the main queue (not Task) keeps the events of one gesture in order.
    private static let contactCallback: ContactCallback = { device, touches, count, _, _ in
        guard let (monitor, detector) = TrackpadSwipeMonitor.active.lookup(device.map(UnsafeRawPointer.init)) else {
            return 0
        }
        let bound = touches?.assumingMemoryBound(to: MTTouch.self)
        let events = detector.process(touches: bound, count: Int(count))
        if !events.isEmpty {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for event in events {
                        monitor.onSwipeEvent?(event)
                    }
                }
            }
        }
        return 0
    }

    /// The resolved private entry points; the non-optional fields never hold
    /// nil — load() fails as a whole when any required symbol is missing.
    private struct Framework {
        var createList: @convention(c) () -> Unmanaged<CFArray>?
        var registerCallback: @convention(c) (MTDeviceRef?, ContactCallback?) -> Void
        var unregisterCallback: @convention(c) (MTDeviceRef?, ContactCallback?) -> Void
        var startDevice: @convention(c) (MTDeviceRef?, Int32) -> Void
        var stopDevice: @convention(c) (MTDeviceRef?) -> Void
        /// Optional because losing it only degrades threshold accuracy, not
        /// the feature; reports the pad size in hundredths of a millimeter.
        var surfaceDimensions: (@convention(c) (
            MTDeviceRef?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?
        ) -> Int32)?

        /// Physical pad size in millimeters, so detector thresholds mean the
        /// same finger travel on every trackpad model. Falls back to
        /// built-in MacBook pad dimensions on implausible values.
        func padSizeMM(of device: MTDeviceRef) -> (width: Float, height: Float) {
            var width: Int32 = 0
            var height: Int32 = 0
            if let surfaceDimensions {
                _ = surfaceDimensions(device, &width, &height)
            }
            guard width > 1000, width < 50000, height > 1000, height < 50000 else {
                return SwipeDetector.fallbackPadSizeMM
            }
            return (Float(width) / 100, Float(height) / 100)
        }

        static func load() -> Framework? {
            let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
            guard let handle = dlopen(path, RTLD_NOW) else {
                return nil
            }

            func symbol<T>(_ name: String, as _: T.Type) -> T? {
                guard let pointer = dlsym(handle, name) else {
                    return nil
                }
                return unsafeBitCast(pointer, to: T.self)
            }

            guard
                let createList = symbol("MTDeviceCreateList", as: (@convention(c) () -> Unmanaged<CFArray>?).self),
                let register = symbol(
                    "MTRegisterContactFrameCallback",
                    as: (@convention(c) (MTDeviceRef?, ContactCallback?) -> Void).self
                ),
                let unregister = symbol(
                    "MTUnregisterContactFrameCallback",
                    as: (@convention(c) (MTDeviceRef?, ContactCallback?) -> Void).self
                ),
                let start = symbol("MTDeviceStart", as: (@convention(c) (MTDeviceRef?, Int32) -> Void).self),
                let stop = symbol("MTDeviceStop", as: (@convention(c) (MTDeviceRef?) -> Void).self)
            else {
                return nil
            }

            return Framework(
                createList: createList,
                registerCallback: register,
                unregisterCallback: unregister,
                startDevice: start,
                stopDevice: stop,
                surfaceDimensions: symbol(
                    "MTDeviceGetSensorSurfaceDimensions",
                    as: (@convention(c) (
                        MTDeviceRef?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?
                    ) -> Int32).self
                )
            )
        }
    }
}

/// Memory layout of one touch as MultitouchSupport reports it, per the
/// community-documented ABI; only `state` and `normalized` are read.
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTReadout
    var total: Float
    var pressure: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTReadout
    var field14: Int32
    var field15: Int32
    var density: Float

    struct MTPoint {
        var horizontal: Float
        var vertical: Float
    }

    struct MTReadout {
        var position: MTPoint
        var velocity: MTPoint
    }

    /// Touch states 3 (make touch) and 4 (touching) mean the finger is on
    /// the pad; lower values are hover, higher values are lift-off.
    var isTouching: Bool {
        state == 3 || state == 4
    }
}

/// The axis a three-finger gesture locked onto.
public enum SwipeAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

/// Lifecycle of one three-finger gesture, in `NSEvent.trackSwipeEvent`
/// style: progress follows the fingers continuously and the outcome is
/// decided when they lift, so a swipe pulled back before release cancels.
public enum SwipeEvent: Equatable, Sendable {
    /// The gesture's travel picked an axis; `moved` events follow.
    case began(SwipeAxis)
    /// Signed progress along the locked axis: +1.0 is the travel a slow
    /// swipe needs to commit one step, toward the right or top of the pad.
    case moved(SwipeAxis, progress: Float)
    /// The fingers lifted. `steps` is the committed step count, clamped to
    /// one step per gesture (negative means left or down); 0 means the
    /// gesture cancelled — pulled back or too short.
    case ended(SwipeAxis, steps: Int)

    public var axis: SwipeAxis {
        switch self {
        case let .began(axis), let .moved(axis, _), let .ended(axis, _):
            axis
        }
    }
}

/// Turns raw contact frames into three-finger gesture events, modeled on how
/// macOS's own gesture engine behaves: thresholds are physical millimeters
/// so every pad size feels alike, the swipe axis locks early in the gesture,
/// all three fingers must move together before it engages, at release a
/// fast flick commits from a shorter distance than a slow drag, and — like
/// the system's Spaces swipe — one gesture commits at most one step. Runs
/// on the MultitouchSupport callback thread; the lock keeps frames from
/// concurrent callbacks from interleaving.
final class SwipeDetector: @unchecked Sendable {
    /// Travel after which the swipe axis locks to the dominant direction.
    private static let axisLockDistanceMM: Float = 3
    /// How decisively one axis must beat the other to lock; until then a
    /// diagonal wobble keeps the gesture undecided rather than guessing.
    private static let axisDominanceRatio: Float = 1.2
    /// Release speed (mm/s along the locked axis) that reads as a
    /// deliberate flick. Below it the lift-off velocity is ignored —
    /// MultitouchSupport's final contact frames commonly report small
    /// spurious velocities as the fingers peel off the pad — and the
    /// outcome comes from position alone.
    private static let flickSpeedMM: Float = 120
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

    /// Decides the commit like a native page swipe. A sub-threshold release
    /// commits the step nearest the fingers — exactly the card a progress
    /// UI highlights at that moment, so display and outcome cannot
    /// diverge. A deliberate flick completes the step the fingers were
    /// headed for in the flick's direction, from however short a distance —
    /// but never more: no release velocity carries the commit past the
    /// next step boundary, and none cancels a boundary already reached.
    /// The epsilon keeps float noise at an exact boundary from leaking or
    /// dropping a step there.
    private func steps(progress: Float, speed: Float) -> Int {
        let epsilon: Float = 0.0001
        let decided: Int
        if speed >= Self.flickSpeedMM {
            decided = Int((progress - epsilon).rounded(.up))
        } else if speed <= -Self.flickSpeedMM {
            decided = Int((progress + epsilon).rounded(.down))
        } else {
            // Half-way releases round away from zero, so the bias follows
            // the travel's sign.
            let bias: Float = progress >= 0 ? epsilon : -epsilon
            decided = Int((progress + bias).rounded())
        }
        // One gesture, one step, like the system's Spaces swipe. A step is
        // 35 mm by default on a ~120 mm-wide pad, so an ordinary swipe's
        // travel alone already spans two to three steps — scrubbing that
        // into multi-step commits made single swipes land unpredictably
        // far. Moving further is a repeat swipe.
        return max(-1, min(1, decided))
    }
}
