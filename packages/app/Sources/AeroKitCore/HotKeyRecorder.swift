import SwiftUI

public struct HotKeyRecorder: View {
    @Binding var spec: HotKeySpec
    var validate: (HotKeySpec) -> Bool = { _ in true }
    let onRecordingChanged: (Bool) -> Void

    public init(
        spec: Binding<HotKeySpec>,
        validate: @escaping (HotKeySpec) -> Bool = { _ in true },
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        _spec = spec
        self.validate = validate
        self.onRecordingChanged = onRecordingChanged
    }

    public var body: some View {
        KeyRecorderButton(
            keys: spec.displayKeys,
            prompt: "Recording…",
            helpText: "Click, then press a key combination with ⌃, ⌥ or ⌘",
            onRecordingChanged: onRecordingChanged
        ) { event in
            guard let recorded = HotKeySpec.from(event: event), validate(recorded) else {
                return false
            }
            spec = recorded
            return true
        }
    }
}
