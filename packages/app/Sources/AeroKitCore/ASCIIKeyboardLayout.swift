import Carbon

/// TIS supplies the most recently used ASCII-capable layout, not necessarily
/// the active input source. Switching to Cyrillic or an IME therefore doesn't
/// replace Latin shortcut names. Resolve on demand; never pin the recording-
/// time layout or assume QWERTY.
@MainActor
enum ASCIIKeyboardLayout {
    static var currentInputSource: TISInputSource? {
        TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
    }

    /// Labels use the base character; built-in Command shortcuts must use the
    /// layout's Command table (notably for Dvorak–QWERTY ⌘).
    static func character(
        for keyCode: UInt16,
        command: Bool = false,
        inputSource: TISInputSource?
    ) -> String? {
        guard let inputSource,
              let property = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let data = unsafeBitCast(property, to: CFData.self)
        // The layout pointer borrows TIS-owned bytes; keep both owners alive
        // through translation, including in optimized release builds.
        return withExtendedLifetime((inputSource, data)) {
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                command ? UInt32(cmdKey >> 8) : 0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else {
                return nil
            }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
