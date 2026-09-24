import AeroKitCore
import AppKit
import SwiftUI

/// Experimental hold-to-cycle switching. The shortcut is the switch:
/// setting one turns the feature on, clearing it turns it off.
struct WindowSwitcherSettingsView: View {
    @ObservedObject var model: WindowSwitcherSettingsModel
    @ObservedObject var preferences: ExposePreferences

    private var heldKeys: String {
        preferences.windowSwitchHotKey?.displayKeys.dropLast().joined(separator: " + ") ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(L10n.tr("Quick window switching (Experimental)")) {
                SettingsRow(
                    title: L10n.tr("Switch to the next window"),
                    subtitle: preferences.windowSwitchHotKey == nil
                        ? L10n.tr("Choose a shortcut to enable window switching.")
                        : L10n.tr("Release \(heldKeys) to select. Add ⇧ to go back; Esc cancels.")
                ) {
                    HotKeyRecorder(
                        spec: $preferences.windowSwitchHotKey,
                        clearable: true
                    ) { model.setHotKeyRecording($0) }
                }
            } accessory: {
                FeatureInfoButton(L10n.tr("Quick window switching (Experimental)")) {
                    QuickWindowSwitchDemo(shortcut: preferences.windowSwitchHotKey?.displayKeys ?? [])
                }
            }
            if let message = model.hotKeyErrorMessage {
                SettingsErrorBanner(L10n.tr(message))
            }
        }
    }
}

private extension WindowSwitcherSettingsModel {
    func setHotKeyRecording(_ isRecording: Bool) {
        self.isRecording = isRecording
        onHotKeyRecordingChanged?(isRecording)
    }
}
