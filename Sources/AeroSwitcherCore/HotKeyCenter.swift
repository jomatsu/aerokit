import Carbon
import Foundation

@MainActor
public final class HotKeyCenter {
    public var onPressed: ((RegisteredHotKey) -> Void)?

    private var hotKeyReferences: [RegisteredHotKey: EventHotKeyRef] = [:]
    private var eventHandlerReference: EventHandlerRef?
    private let signature = OSType(0x4153_5748)

    public init() {}

    public func register(_ hotKey: RegisteredHotKey) throws {
        guard hotKeyReferences[hotKey] == nil else {
            return
        }

        try installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: hotKey.rawValue)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else {
            throw HotKeyError.registerFailed(status)
        }

        hotKeyReferences[hotKey] = reference
    }

    public func unregister(_ hotKey: RegisteredHotKey) {
        guard let reference = hotKeyReferences.removeValue(forKey: hotKey) else {
            return
        }
        UnregisterEventHotKey(reference)
    }

    public func unregisterAll() {
        for hotKey in Array(hotKeyReferences.keys) {
            unregister(hotKey)
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

                guard status == noErr, let hotKey = RegisteredHotKey(rawValue: identifier.id) else {
                    return noErr
                }

                Task { @MainActor in
                    center.onPressed?(hotKey)
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

public enum RegisteredHotKey: UInt32, Sendable {
    case optionBacktick = 1
    case escape = 2

    var keyCode: UInt32 {
        switch self {
        case .optionBacktick:
            UInt32(kVK_ANSI_Grave)
        case .escape:
            UInt32(kVK_Escape)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionBacktick:
            UInt32(optionKey)
        case .escape:
            0
        }
    }
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
