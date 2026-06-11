import AeroKitCore
import AppKit
import SwiftUI

/// Records the single unmodified key that toggles grouping in the overview.
/// Keys the overview reserves for itself (Return, Space, Tab, arrows) and
/// non-ASCII input are refused.
struct CharacterKeyRecorder: View {
    @Binding var key: String
    let onRecordingChanged: (Bool) -> Void

    private static let reservedKeyCodes: Set<UInt16> = [
        KeyCode.return, KeyCode.keypadEnter, KeyCode.space, KeyCode.tab,
        KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow, KeyCode.downArrow
    ]

    var body: some View {
        KeyRecorderButton(
            keys: [key.uppercased()],
            prompt: "Press a key",
            helpText: "Click, then press the key that toggles grouping while the overview is open",
            onRecordingChanged: onRecordingChanged
        ) { event in
            guard !Self.reservedKeyCodes.contains(event.keyCode),
                  let character = event.charactersIgnoringModifiers?.first,
                  character.isASCII,
                  character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
            else {
                return false
            }
            key = String(character).uppercased()
            return true
        }
    }
}
