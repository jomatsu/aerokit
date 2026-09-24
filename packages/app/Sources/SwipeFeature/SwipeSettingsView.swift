import AeroKitCore
import AppKit
import SwiftUI

/// Three-finger horizontal swipes between workspaces.
struct SwipeSettingsView: View {
    @ObservedObject var model: SwipeSettingsModel
    @ObservedObject var preferences: SwipePreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            trackpadSection
            if let message = model.swipeErrorMessage {
                SettingsErrorBanner(L10n.tr(message))
            }
            if let message = model.systemGestureConflictMessage {
                SettingsErrorBanner(L10n.tr(message))
            }
        }
        .onAppear { refreshStatus() }
        .onChange(of: preferences.isEnabled) { refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    private func refreshStatus() {
        model.refreshSystemGestureConflict(gestureEnabled: preferences.isEnabled)
    }

    private var trackpadSection: some View {
        SettingsSection(L10n.tr("Swipe between workspaces")) {
            SettingsToggleRow(
                L10n.tr("Use three fingers to switch workspaces"),
                subtitle: L10n.tr("Swipe sideways on your trackpad to change workspaces."),
                isOn: $preferences.isEnabled
            )
            SettingsDivider()
            SettingsRow(
                title: L10n.tr("Swipe direction"),
                subtitle: preferences.naturalDirection
                    ? L10n.tr("Swipe left to go to the next workspace.")
                    : L10n.tr("Swipe right to go to the next workspace.")
            ) {
                Picker(L10n.tr("Swipe direction"), selection: $preferences.naturalDirection) {
                    Text(L10n.tr("Natural")).tag(true)
                    Text(L10n.tr("Reversed")).tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(!preferences.isEnabled)
            }
            SettingsDivider()
            SwipeDistanceControl(distance: $preferences.stepDistanceMM)
                .disabled(!preferences.isEnabled)
            SettingsDivider()
            navigationRows
        } accessory: {
            FeatureInfoButton(L10n.tr("Swipe between workspaces")) {
                WorkspaceSwipeDemoHost(preferences: preferences)
            }
        }
    }

    @ViewBuilder private var navigationRows: some View {
        SettingsToggleRow(
            L10n.tr("Visit empty workspaces too"),
            subtitle: L10n.tr("Swipes stop at every workspace, including empty ones."),
            isOn: Binding(get: { !preferences.skipEmpty }, set: { preferences.skipEmpty = !$0 })
        )
        .disabled(!preferences.isEnabled)
        SettingsDivider()
        SettingsToggleRow(
            L10n.tr("Continue from the first workspace after the last"),
            subtitle: L10n.tr("Last → First. You can keep swiping in the same direction."),
            isOn: $preferences.wrapAround
        )
        .disabled(!preferences.isEnabled)
    }
}

@MainActor
final class SwipeSettingsModel: ObservableObject {
    @Published var swipeErrorMessage: LocalizedStringResource?
    @Published var systemGestureConflictMessage: LocalizedStringResource?

    /// The system's three-finger Space swipe cannot be consumed, so while
    /// it is on, every workspace swipe also slides the screen to another
    /// macOS Space. There is no reliable programmatic fix (the trackpad
    /// preference only applies on re-login), so surface the exact setting
    /// to change instead of a button.
    func refreshSystemGestureConflict(gestureEnabled: Bool) {
        systemGestureConflictMessage = gestureEnabled
            && SystemSwipeGestures.horizontalThreeFingerSpaceSwipeEnabled
            ? """
            macOS also reacts to three-finger horizontal swipes and slides \
            to another Space over the switched workspace. Set System \
            Settings → Trackpad → More Gestures → “Swipe between \
            full-screen applications” to Off or four fingers.
            """
            : nil
    }
}

/// The swipe demo bound to the live direction setting.
struct WorkspaceSwipeDemoHost: View {
    @ObservedObject var preferences: SwipePreferences

    var body: some View {
        WorkspaceSwipeDemo(naturalDirection: preferences.naturalDirection)
    }
}
