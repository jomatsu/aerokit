import AeroKitCore
import SwiftUI

struct ExposeSettingsView: View {
    @ObservedObject var model: ExposeSettingsModel
    @ObservedObject var preferences: ExposePreferences

    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            shortcutsSection

            if let message = model.hotKeyErrorMessage {
                SettingsErrorBanner(message)
            }

            if let message = model.appHotKeyErrorMessage {
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
                    subtitle: "1–9 / A–Z focus · arrows move · \(preferences.groupToggleKey) groups · Esc dismisses"
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

    private var shortcutsSection: some View {
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
                title: "Show app windows",
                subtitle: "Lay out the focused app's windows from every workspace"
            ) {
                HotKeyRecorder(spec: $preferences.appHotKey) { isRecording in
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
            SettingsDivider()
            SettingsRow(
                title: "Group overview by app",
                subtitle: "Cluster the workspace overview into per-app cards"
            ) {
                SettingsToggle(isOn: $preferences.groupByApp)
            }
            SettingsDivider()
            SettingsRow(
                title: "Grouping toggle key",
                subtitle: "Flips grouping while the overview is open \u{B7} quick select skips this key"
            ) {
                CharacterKeyRecorder(key: $preferences.groupToggleKey) { isRecording in
                    model.setHotKeyRecording(isRecording)
                }
            }
            SettingsDivider()
            SettingsRow(
                title: "Show grouping shortcut hint",
                subtitle: "Display the \(preferences.groupToggleKey) key hint at the bottom of the overview"
            ) {
                SettingsToggle(isOn: $preferences.showGroupToggleHint)
            }
        }
    }
}

@MainActor
final class ExposeSettingsModel: ObservableObject {
    @Published var hotKeyErrorMessage: String?
    @Published var appHotKeyErrorMessage: String?

    var onHotKeyRecordingChanged: ((Bool) -> Void)?

    /// Counted because the pane has one recorder per hotkey and the user can
    /// start the second before finishing the first; the global triggers must
    /// stay suspended until no recorder is active.
    private var activeRecorders = 0

    func setHotKeyRecording(_ isRecording: Bool) {
        let wasRecording = activeRecorders > 0
        activeRecorders = max(0, activeRecorders + (isRecording ? 1 : -1))
        let isRecordingNow = activeRecorders > 0
        if wasRecording != isRecordingNow {
            onHotKeyRecordingChanged?(isRecordingNow)
        }
    }
}
