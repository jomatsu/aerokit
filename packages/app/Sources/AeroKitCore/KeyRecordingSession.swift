import AppKit
import Combine

@MainActor
public final class KeyRecordingSession: ObservableObject {
    public static let shared = KeyRecordingSession()
    @Published public private(set) var activeID: UUID?
    @Published public private(set) var errorMessage: String?

    private let recordingChanges = PassthroughSubject<Bool, Never>()
    public var recordingChanged: AnyPublisher<Bool, Never> {
        recordingChanges.eraseToAnyPublisher()
    }

    private var record: ((NSEvent) -> String?)?
    private var onRecordingChanged: ((Bool) -> Void)?
    private var containsClick: ((NSEvent) -> Bool)?
    private var eventMonitor: Any?
    private var activationObserver: (any NSObjectProtocol)?

    public init() {}

    public func start(
        id: UUID,
        containsClick: @escaping (NSEvent) -> Bool,
        onRecordingChanged: @escaping (Bool) -> Void,
        record: @escaping (NSEvent) -> String?
    ) {
        stop()
        activeID = id
        errorMessage = nil
        self.record = record
        self.containsClick = containsClick
        self.onRecordingChanged = onRecordingChanged
        recordingChanges.send(true)
        onRecordingChanged(true)
        let events: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// True consumes a key; mouse clicks continue to their destination after cancellation.
    @discardableResult
    public func handle(_ event: NSEvent) -> Bool {
        guard activeID != nil else { return false }
        if event.type != .keyDown {
            if containsClick?(event) != true {
                stop()
            }
            return false
        }
        if KeyCode.isBareEscape(event) {
            stop()
        } else if let error = record?(event) {
            errorMessage = error
        } else {
            stop()
        }
        return true
    }

    public func stop(id: UUID? = nil) {
        if let id, id != activeID {
            return
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        eventMonitor = nil
        activationObserver = nil
        let callback = onRecordingChanged
        let wasActive = activeID != nil
        activeID = nil
        errorMessage = nil
        record = nil
        containsClick = nil
        onRecordingChanged = nil
        if wasActive {
            recordingChanges.send(false)
            callback?(false)
        }
    }
}
