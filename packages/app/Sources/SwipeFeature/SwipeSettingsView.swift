import AeroKitCore
import SwiftUI

struct SwipeSettingsView: View {
    @ObservedObject var model: SwipeSettingsModel
    @ObservedObject var preferences: SwipePreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            trackpadSection
            behaviorSection

            if let message = model.swipeErrorMessage {
                SettingsErrorBanner(message)
            }
        }
    }

    private var trackpadSection: some View {
        SettingsSection("Trackpad") {
            SettingsRow(
                title: "Three-finger horizontal swipe",
                subtitle: "Swipe left or right to switch AeroSpace workspaces"
            ) {
                SettingsToggle(isOn: $preferences.isEnabled)
            }
            SettingsDivider()
            SettingsRow(
                title: "Natural direction",
                subtitle: "Content follows your fingers: swiping left moves to the workspace on the right"
            ) {
                SettingsToggle(isOn: $preferences.naturalDirection, isEnabled: preferences.isEnabled)
            }
        }
    }

    private var behaviorSection: some View {
        SettingsSection("Behavior") {
            SettingsRow(
                title: "Wrap around",
                subtitle: "Swiping past the last workspace continues from the first"
            ) {
                SettingsToggle(isOn: $preferences.wrapAround, isEnabled: preferences.isEnabled)
            }
            SettingsDivider()
            SettingsRow(
                title: "Skip empty workspaces",
                subtitle: "Step over workspaces that have no windows"
            ) {
                SettingsToggle(isOn: $preferences.skipEmpty, isEnabled: preferences.isEnabled)
            }
            SettingsDivider()
            SettingsRow(
                title: "Show workspace strip",
                subtitle: "Briefly display the workspace list after every switch"
            ) {
                SettingsToggle(isOn: $preferences.showHUD, isEnabled: preferences.isEnabled)
            }
        }
    }
}

@MainActor
final class SwipeSettingsModel: ObservableObject {
    @Published var swipeErrorMessage: String?
}
