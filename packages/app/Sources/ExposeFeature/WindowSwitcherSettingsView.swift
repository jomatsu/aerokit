import AeroKitCore
import AppKit
import SwiftUI

/// The window switcher's settings section, embedded in the Exposé pane:
/// ships off; enabling reveals the hotkey recorder and the two setup
/// warnings (AeroSpace's own alt-tab binding, Accessibility for the
/// global tap).
struct WindowSwitcherSettingsView: View {
    @ObservedObject var model: WindowSwitcherSettingsModel
    @ObservedObject var preferences: ExposePreferences

    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Window Switcher (Experimental)") {
                SettingsRow(
                    title: "Enable window cycling",
                    subtitle: "Cycle the focused workspace's windows; release to commit"
                ) {
                    SettingsToggle(isOn: $preferences.windowSwitchEnabled)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Window switcher hotkey",
                    subtitle: "Tap to advance · ⇧ reverses · release commits · Esc cancels"
                ) {
                    HotKeyRecorder(spec: $preferences.windowSwitchHotKey) { isRecording in
                        model.setHotKeyRecording(isRecording)
                    }
                }
                .disabled(!preferences.windowSwitchEnabled)
            }

            if let message = model.hotKeyErrorMessage {
                SettingsErrorBanner(message)
            }

            if preferences.windowSwitchEnabled {
                if !accessibilityGranted {
                    SettingsErrorBanner(
                        "Without Accessibility access the strip falls back to panel keys and can miss "
                            + "releases when another window keeps focus.",
                        icon: "hand.raised.fill",
                        actionTitle: "Grant\u{2026}"
                    ) {
                        AccessibilityPermission.request()
                    }
                }
                SettingsErrorBanner(
                    "AeroSpace's default config binds alt-tab. If the hotkey above conflicts, change it "
                        + "here or in ~/.aerospace.toml.",
                    icon: "exclamationmark.triangle"
                )
            }
        }
        .onAppear {
            accessibilityGranted = AccessibilityPermission.isGranted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AccessibilityPermission.isGranted
        }
    }
}

private extension WindowSwitcherSettingsModel {
    func setHotKeyRecording(_ isRecording: Bool) {
        self.isRecording = isRecording
        onHotKeyRecordingChanged?(isRecording)
    }
}
