import SwiftUI

public struct HotKeyRecorder: View {
    @Binding var spec: HotKeySpec?
    var validate: (HotKeySpec) -> Bool = { _ in true }
    /// Offers a clear button, for optional shortcuts whose absence turns
    /// their feature off.
    var clearable = false
    let onRecordingChanged: (Bool) -> Void

    public init(
        spec: Binding<HotKeySpec>,
        validate: @escaping (HotKeySpec) -> Bool = { _ in true },
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        self.init(
            spec: Binding<HotKeySpec?>(
                get: { spec.wrappedValue },
                set: {
                    if let value = $0 {
                        spec.wrappedValue = value
                    }
                }
            ),
            validate: validate,
            onRecordingChanged: onRecordingChanged
        )
    }

    public init(
        spec: Binding<HotKeySpec?>,
        validate: @escaping (HotKeySpec) -> Bool = { _ in true },
        clearable: Bool = false,
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        _spec = spec
        self.validate = validate
        self.clearable = clearable
        self.onRecordingChanged = onRecordingChanged
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 6) {
            recorder
            if clearable, spec != nil {
                ClearShortcutButton { spec = nil }
            }
        }
    }

    private var recorder: some View {
        KeyRecorderButton(
            keys: spec?.displayKeys ?? [],
            prompt: L10n.tr("Press shortcut…"),
            helpText: L10n.tr("Include ⌃, ⌥ or ⌘"),
            onRecordingChanged: onRecordingChanged
        ) { event in
            guard let recorded = HotKeySpec.from(event: event) else {
                return L10n.tr("Include ⌃, ⌥ or ⌘ in the shortcut. Esc cancels.")
            }
            guard validate(recorded) else {
                return L10n.tr("This shortcut is already in use. Try another combination.")
            }
            spec = recorded
            return nil
        }
    }
}

private struct ClearShortcutButton: View {
    @Environment(\.settingsControlLabel)
    private var label
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.tr("Remove this shortcut"))
        .accessibilityLabel(L10n.tr("Remove \(label) shortcut"))
    }
}
