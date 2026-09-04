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
