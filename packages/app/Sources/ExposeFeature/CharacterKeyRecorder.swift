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
            prompt: L10n.tr("Press a key"),
            helpText: L10n.tr("Press one letter, number or symbol"),
            onRecordingChanged: onRecordingChanged
        ) { event in
            guard event.modifierFlags.isDisjoint(with: [.command, .option, .control]),
                  !Self.reservedKeyCodes.contains(event.keyCode),
                  let character = event.charactersIgnoringModifiers?.first,
                  character.isASCII,
                  character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
            else {
                return L10n.tr("Use a letter, number or symbol without ⌃, ⌥ or ⌘. Esc cancels.")
            }
            key = String(character).uppercased()
            return nil
        }
    }
}
