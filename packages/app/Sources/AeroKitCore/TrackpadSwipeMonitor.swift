import AppKit
import Darwin
import Foundation

/// Detects three-finger swipes on Apple trackpads through the private
/// MultitouchSupport framework — the only way to observe trackpad touches
/// globally, since NSEvent gesture events only reach the app's own windows.
/// The framework is loaded with dlopen/dlsym so the build carries no
/// link-time dependency on a private framework.
@MainActor
public final class TrackpadSwipeMonitor {
    public enum Direction: Sendable {
        case up
        case down
    }

    /// Called on the main actor whenever a three-finger swipe crosses the
    /// distance threshold; fires once per touch-down.
    public var onSwipe: ((Direction) -> Void)?

    public private(set) var isRunning = false

    /// Routes the C callback — which cannot capture context — back to the
    /// monitor that registered it. Lock-protected because start()/stop()
    /// assign on the main actor while the callback reads on a
    /// MultitouchSupport thread. Only one monitor runs at a time.
    private static let active = LockedWeakMonitor()

    private final class LockedWeakMonitor: @unchecked Sendable {
        private let lock = NSLock()
        private weak var monitor: TrackpadSwipeMonitor?

        func get() -> TrackpadSwipeMonitor? {
            lock.lock()
            defer { lock.unlock() }
            return monitor
        }

        func set(_ monitor: TrackpadSwipeMonitor?) {
            lock.lock()
            defer { lock.unlock() }
            self.monitor = monitor
        }
    }

    private let detector = SwipeDetector()
    private var devices: CFArray?
    private var framework: Framework?

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

        Self.active.set(self)
        devices = list
        for index in 0 ..< CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else {
                continue
            }
            let reference = MTDeviceRef(mutating: device)
            framework.registerCallback(reference, Self.contactCallback)
            framework.startDevice(reference, 0)
        }
        isRunning = true
        return true
    }

    public func stop() {
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
        Self.active.set(nil)
        // A gesture in progress at stop time must not leave a stale
        // baseline behind for the next start().
        detector.reset()
        isRunning = false
    }

    // MARK: - MultitouchSupport bridging

    private typealias MTDeviceRef = UnsafeMutableRawPointer
    /// The touches parameter is really `MTTouch *`; it stays a raw pointer
    /// because @convention(c) cannot mention a Swift-declared struct.
    fileprivate typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32
    ) -> Int32

    /// Delivered on a MultitouchSupport background thread.
    private static let contactCallback: ContactCallback = { _, touches, count, _, _ in
        guard let monitor = TrackpadSwipeMonitor.active.get() else {
            return 0
        }
        let bound = touches?.assumingMemoryBound(to: MTTouch.self)
        if let direction = monitor.detector.process(touches: bound, count: Int(count)) {
            Task { @MainActor in
                monitor.onSwipe?(direction)
            }
        }
        return 0
    }

    /// The resolved private entry points; nil fields never occur — load()
    /// fails as a whole when any symbol is missing.
    private struct Framework {
        var createList: @convention(c) () -> Unmanaged<CFArray>?
        var registerCallback: @convention(c) (MTDeviceRef?, ContactCallback?) -> Void
        var unregisterCallback: @convention(c) (MTDeviceRef?, ContactCallback?) -> Void
        var startDevice: @convention(c) (MTDeviceRef?, Int32) -> Void
        var stopDevice: @convention(c) (MTDeviceRef?) -> Void

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
                stopDevice: stop
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

/// Turns raw contact frames into at most one swipe per touch-down. Runs on
/// the MultitouchSupport callback thread; the lock keeps frames from
/// multiple devices from interleaving.
final class SwipeDetector: @unchecked Sendable {
    /// Normalized trackpad units (the pad is 0…1 on both axes) the average
    /// finger position must travel before a swipe fires.
    private static let threshold: Float = 0.12

    private let lock = NSLock()
    private var isTracking = false
    private var hasFired = false
    private var startX: Float = 0
    private var startY: Float = 0

    /// Forgets any in-flight gesture so a restarted monitor measures from
    /// a fresh baseline instead of a stale one.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        isTracking = false
        hasFired = false
    }

    func process(touches: UnsafePointer<MTTouch>?, count: Int) -> TrackpadSwipeMonitor.Direction? {
        lock.lock()
        defer { lock.unlock() }

        var sumX: Float = 0
        var sumY: Float = 0
        var touching = 0
        if let touches {
            for index in 0 ..< count where touches[index].isTouching {
                touching += 1
                sumX += touches[index].normalized.position.horizontal
                sumY += touches[index].normalized.position.vertical
            }
        }

        // Anything other than exactly three fingers ends the gesture; the
        // next three-finger frame starts a fresh baseline.
        guard touching == 3 else {
            isTracking = false
            return nil
        }

        let averageX = sumX / 3
        let averageY = sumY / 3
        if !isTracking {
            isTracking = true
            hasFired = false
            startX = averageX
            startY = averageY
            return nil
        }

        guard !hasFired else {
            return nil
        }
        let deltaX = averageX - startX
        let deltaY = averageY - startY
        guard abs(deltaY) >= Self.threshold, abs(deltaY) > abs(deltaX) else {
            return nil
        }
        hasFired = true
        // Normalized y grows toward the top edge of the pad.
        return deltaY > 0 ? .up : .down
    }
}
