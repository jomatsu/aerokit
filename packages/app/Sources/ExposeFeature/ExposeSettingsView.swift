import AeroKitCore
import SwiftUI

struct ExposeSettingsView: View {
    @ObservedObject var model: ExposeSettingsModel
    @ObservedObject var preferences: ExposePreferences

    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            shortcutsSection
            trackpadSection

            if let message = model.hotKeyErrorMessage {
                SettingsErrorBanner(message)
            }

            if let message = model.appHotKeyErrorMessage {
                SettingsErrorBanner(message)
            }

            if let message = model.swipeErrorMessage {
                SettingsErrorBanner(message)
            }

            if let message = model.systemGestureErrorMessage {
                SettingsErrorBanner(message)
            }

            if preferences.threeFingerSwipe, model.systemGesturesEnabled {
                SettingsErrorBanner(
                    "The system Mission Control gestures are also on, so both will react to three-finger swipes.",
                    icon: "hand.draw.fill",
                    actionTitle: "Turn Off\u{2026}"
                ) {
                    model.setSystemGestures(false)
                }
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
            model.refreshSystemGestures()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from System Settings after granting access or
            // flipping the gesture checkboxes there.
            accessibilityGranted = AccessibilityPermission.isGranted
            model.refreshSystemGestures()
        }
    }

    private var trackpadSection: some View {
        SettingsSection("Trackpad") {
            SettingsRow(
                title: "Three-finger swipe",
                subtitle: "Swipe up for overview, down for app windows"
            ) {
                SettingsToggle(isOn: $preferences.threeFingerSwipe)
            }
            SettingsDivider()
            SettingsRow(
                title: "System swipe gestures",
                subtitle: "macOS Mission Control & App Exposé on three-finger swipe \u{B7} changing restarts the Dock"
            ) {
                SettingsToggle(isOn: Binding(
                    get: { model.systemGesturesEnabled },
                    set: { model.setSystemGestures($0) }
                ))
            }
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
            SettingsDivider()
            SettingsRow(
                title: "Follow moved window",
                subtitle: "After \u{21E7}1\u{2013}9 or a drag moves a window, switch to its workspace instead of staying in the overview"
            ) {
                SettingsToggle(isOn: $preferences.followMovedWindow)
            }
        }
    }
}

@MainActor
final class ExposeSettingsModel: ObservableObject {
    @Published var hotKeyErrorMessage: String?
    @Published var appHotKeyErrorMessage: String?
    @Published var swipeErrorMessage: String?
    @Published var systemGestureErrorMessage: String?

    /// Mirror of the macOS Mission Control / App Exposé gesture checkboxes;
    /// refreshed whenever the pane (re)appears because System Settings can
    /// change them behind our back.
    @Published var systemGesturesEnabled = SystemSwipeGestures.isEnabled

    var onHotKeyRecordingChanged: ((Bool) -> Void)?

    /// Chained so rapid toggling cannot interleave two write-and-restart
    /// sequences and leave the system disagreeing with the toggle.
    private var systemGestureWrite: Task<Void, Never>?

    func refreshSystemGestures() {
        systemGesturesEnabled = SystemSwipeGestures.isEnabled
    }

    /// Optimistically flips the toggle, then writes the Dock preferences
    /// and restarts the Dock off-main; a failure resyncs from the system.
    func setSystemGestures(_ enabled: Bool) {
        systemGesturesEnabled = enabled
        systemGestureErrorMessage = nil
        systemGestureWrite = Task.detached(priority: .userInitiated) { [previousWrite = systemGestureWrite] in
            await previousWrite?.value
            do {
                try SystemSwipeGestures.setEnabled(enabled)
            } catch {
                fputs("AeroKit: updating system swipe gestures failed: \(error)\n", stderr)
                await MainActor.run {
                    self.systemGestureErrorMessage = "Could not change the system swipe gestures."
                    self.refreshSystemGestures()
                }
            }
        }
    }

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
