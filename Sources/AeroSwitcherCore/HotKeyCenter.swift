import Carbon
import Foundation

@MainActor
public final class HotKeyCenter {
    public var onPressed: ((HotKeyRole) -> Void)?

    private var hotKeyReferences: [HotKeyRole: EventHotKeyRef] = [:]
    private var eventHandlerReference: EventHandlerRef?
    private let signature = OSType(0x4153_5748)

    public init() {}

    public func register(_ role: HotKeyRole, keyCode: UInt32, modifiers: UInt32) throws {
        guard hotKeyReferences[role] == nil else {
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

        hotKeyReferences[role] = reference
    }

    public func unregister(_ role: HotKeyRole) {
        guard let reference = hotKeyReferences.removeValue(forKey: role) else {
            return
        }
        UnregisterEventHotKey(reference)
    }

    public func unregisterAll() {
        for role in Array(hotKeyReferences.keys) {
            unregister(role)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private func installHandlerIfNeeded() throws {
        guard eventHandlerReference == nil else {
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
            &eventHandlerReference
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
