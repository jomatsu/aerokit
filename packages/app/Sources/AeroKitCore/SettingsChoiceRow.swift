import SwiftUI

/// Two named outcomes for a setting that reads poorly as an on/off switch.
/// A compact segmented control; the subtitle explains only the chosen side.
public struct SettingsChoiceRow: View {
    public struct Option {
        let title: String
        let detail: String

        public init(_ title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    let title: String
    @Binding var isOn: Bool
    let off: Option
    let on: Option

    public init(_ title: String, isOn: Binding<Bool>, off: Option, on: Option) {
        self.title = title
        _isOn = isOn
        self.off = off
        self.on = on
    }

    public var body: some View {
        SettingsRow(title: title, subtitle: isOn ? on.detail : off.detail) {
            Picker(title, selection: $isOn) {
                Text(off.title).tag(false)
                Text(on.title).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}
