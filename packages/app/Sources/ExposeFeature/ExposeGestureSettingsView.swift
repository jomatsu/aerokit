import AeroKitCore
import SwiftUI

struct ExposeGestureSettingsView: View {
    @ObservedObject var model: ExposeSettingsModel
    @ObservedObject var preferences: ExposePreferences
    var showOverview: () -> Void
    var showAppWindows: () -> Void
    @State private var confirmingSystemChange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            gestureSection
            if let message = model.swipeErrorMessage {
                SettingsErrorBanner(L10n.tr(message))
            }
            if let message = model.systemGestureErrorMessage {
                SettingsErrorBanner(L10n.tr(message))
            }
        }
        .onAppear { model.refreshSystemGestures() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSystemGestures()
        }
        .alert(L10n.tr("Change macOS gestures?"), isPresented: $confirmingSystemChange) {
            Button(L10n.tr("Cancel"), role: .cancel) {}
            Button(model.systemGesturesEnabled ? L10n.tr("Turn Off and Restart Dock") : L10n
                .tr("Turn On and Restart Dock"))
            {
                model.setSystemGestures(!model.systemGesturesEnabled)
            }
        } message: {
            Text(
                L10n.tr("""
                This changes Mission Control and App Exposé gestures for all apps. The Dock will \
                disappear briefly while it restarts. You can restore these settings here or in \
                System Settings.
                """)
            )
        }
    }

    private var gestureSection: some View {
        SettingsSection(L10n.tr("Vertical gestures")) {
            SettingsToggleRow(
                L10n.tr("Use three fingers to show windows"),
                subtitle: L10n.tr("↑ Window overview · ↓ Current app’s windows"),
                isOn: $preferences.threeFingerSwipe
            )
            HStack(spacing: 12) {
                gestureHint(
                    L10n.tr("Swipe up"),
                    result: L10n.tr("This workspace’s windows"),
                    icon: "arrow.up",
                    windows: "square.grid.2x2",
                    action: showOverview
                )
                gestureHint(
                    L10n.tr("Swipe down"),
                    result: L10n.tr("This app’s windows"),
                    icon: "arrow.down",
                    windows: "macwindow.on.rectangle",
                    action: showAppWindows
                )
            }.padding([.horizontal, .bottom], 16).opacity(preferences.threeFingerSwipe ? 1 : 0.45)
            SettingsDivider()
            systemGestureRow
        } accessory: {
            FeatureInfoButton(L10n.tr("Vertical gestures")) { VerticalGestureDemo() }
        }
    }

    private var systemGestureRow: some View {
        SettingsRow(
            title: L10n.tr("macOS vertical gestures"),
            subtitle: preferences.threeFingerSwipe
                ? L10n.tr("Keep Mission Control and App Exposé gestures off so they don’t open alongside AeroKit.")
                : L10n.tr("AeroKit’s vertical gestures are off. You can use the macOS gestures instead.")
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                systemGestureStatus
                if preferences.threeFingerSwipe, !model.systemGesturesEnabled {
                    Text(L10n.tr("No changes needed.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(systemGestureActionTitle) { confirmingSystemChange = true }
                }
            }
        }
    }

    private var systemGestureStatus: some View {
        Group {
            if preferences.threeFingerSwipe {
                Label(
                    model.systemGesturesEnabled ? L10n.tr("On (May conflict)") : L10n.tr("Off (Recommended)"),
                    systemImage: model.systemGesturesEnabled ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(model.systemGesturesEnabled ? Color.orange : Color.green)
            } else {
                Text(model.systemGesturesEnabled ? L10n.tr("On in macOS") : L10n.tr("Off in macOS"))
                    .foregroundStyle(.secondary)
            }
        }.font(.caption)
    }

    private var systemGestureActionTitle: String {
        if model.systemGesturesEnabled {
            return preferences.threeFingerSwipe ? L10n.tr("Turn Off for AeroKit…") : L10n.tr("Turn Off in macOS…")
        }
        return L10n.tr("Turn On in macOS…")
    }

    private func gestureHint(
        _ title: String,
        result: String,
        icon: String,
        windows: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                Image(systemName: "hand.draw")
            }.foregroundStyle(Color.accentColor)
            Image(systemName: windows).font(.system(size: 22)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(result).font(.system(size: 11)).foregroundStyle(.secondary)
                Button(L10n.tr("Try"), action: action)
                    .accessibilityLabel(L10n.tr("Try: \(result)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}
