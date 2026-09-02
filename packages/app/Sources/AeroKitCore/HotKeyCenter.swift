import Carbon
import Foundation

@MainActor
public final class HotKeyCenter {
    /// Owns the Carbon registrations so they are torn down when the center
    /// deallocates: the installed handler holds an unretained pointer to the
    /// center, so it must not outlive it. Lives in its own class because a
    /// nonisolated deinit cannot touch MainActor state directly.
    ///
    /// `@unchecked` because all access happens on the MainActor and deinit
    /// runs with exclusive access to the last reference.
    private final class CarbonReferences: @unchecked Sendable {
        var hotKeys: [HotKeyRole: EventHotKeyRef] = [:]
        var eventHandler: EventHandlerRef?

        deinit {
            for reference in hotKeys.values {
                UnregisterEventHotKey(reference)
            }
            if let eventHandler {
                RemoveEventHandler(eventHandler)
            }
        }
    }

    public var onPressed: ((HotKeyRole) -> Void)?

    private let references = CarbonReferences()
    private let signature = OSType(0x414B_4854) // 'AKHT'

    public init() {}

    public func register(_ role: HotKeyRole, keyCode: UInt32, modifiers: UInt32) throws {
        guard references.hotKeys[role] == nil else {
            return
        }

        try installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: role.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else {
            throw HotKeyError.registerFailed(status)
        }

        references.hotKeys[role] = reference
    }

    public func unregister(_ role: HotKeyRole) {
        guard let reference = references.hotKeys.removeValue(forKey: role) else {
            return
        }
        UnregisterEventHotKey(reference)
    }

    private func installHandlerIfNeeded() throws {
        guard references.eventHandler == nil else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )

                guard status == noErr, let role = HotKeyRole(rawValue: identifier.id) else {
                    return noErr
                }

                Task { @MainActor in
                    center.onPressed?(role)
                }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &references.eventHandler
        )
        guard handlerStatus == noErr else {
            throw HotKeyError.installHandlerFailed(handlerStatus)
        }
    }
}

public enum HotKeyRole: UInt32, Sendable {
    case cycleForward = 1
    case escape = 2
    case cycleBackward = 3
    case exposeToggle = 4
    case exposeAppToggle = 5
    case windowCycleForward = 6
    case windowCycleBackward = 7
}

public enum HotKeyError: Error, CustomStringConvertible {
    case installHandlerFailed(OSStatus)
    case registerFailed(OSStatus)

    public var description: String {
        switch self {
        case let .installHandlerFailed(status):
            "InstallEventHandler failed with status \(status)"
        case let .registerFailed(status):
            "RegisterEventHotKey failed with status \(status)"
        }
    }
}
