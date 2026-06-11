import AeroKitCore
import SwiftUI

struct ExposeSettingsView: View {
    @ObservedObject var model: ExposeSettingsModel
    @ObservedObject var preferences: ExposePreferences

    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Shortcuts") {
                SettingsRow(
                    title: "Show window overview",
                    subtitle: "Lay out the focused workspace's windows in a grid"
                ) {
                    HotKeyRecorder(spec: $preferences.hotKey) { isRecording in
                        model.setHotKeyRecording(isRecording)
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "\u{2325} + number selects windows",
                    subtitle: "\u{2325}1\u{2013}9 focuses a window instead of switching AeroSpace workspaces"
                ) {
                    SettingsToggle(isOn: $preferences.modifierQuickSelect)
                }
            }

            if let message = model.hotKeyErrorMessage {
                SettingsErrorBanner(message)
            }

            if preferences.modifierQuickSelect, !accessibilityGranted {
                SettingsErrorBanner(
                    "Claiming \u{2325}1\u{2013}9 before AeroSpace needs Accessibility access.",
                    icon: "hand.raised.fill",
                    actionTitle: "Grant\u{2026}"
                ) {
                    AccessibilityPermission.request()
                }
            }

            SettingsSection("Tips") {
                SettingsRow(
                    title: "While the overview is open",
                    subtitle: "Click or press 1–9 to focus a window · arrows move · Esc dismisses"
                ) {
                    EmptyView()
                }
            }
        }
        .onAppear {
            accessibilityGranted = AccessibilityPermission.isGranted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from System Settings after granting access.
            accessibilityGranted = AccessibilityPermission.isGranted
        }
    }
}

@MainActor
final class ExposeSettingsModel: ObservableObject {
    @Published var hotKeyErrorMessage: String?

    var onHotKeyRecordingChanged: ((Bool) -> Void)?

    func setHotKeyRecording(_ isRecording: Bool) {
        onHotKeyRecordingChanged?(isRecording)
    }
}
