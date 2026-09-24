import AeroKitCore
import SwiftUI

/// The window overview's whole setup in one section: both shortcuts, the
/// arrangement and its toggle key, and what happens after a move.
struct WindowOverviewSettingsView: View {
    @ObservedObject var model: ExposeSettingsModel
    @ObservedObject var preferences: ExposePreferences
    var showOverview: () -> Void
    var showAppWindows: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(L10n.tr("Window overview")) {
                shortcutRows
                SettingsDivider()
                arrangementRows
                Text(L10n.tr("1–9 / A–Z selects · arrows move · Esc closes"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom], 16)
            } accessory: {
                FeatureInfoButton(L10n.tr("Window overview")) {
                    WindowOverviewDemoHost(preferences: preferences)
                }
            }
            if let message = model.hotKeyErrorMessage {
                SettingsErrorBanner(L10n.tr(message))
            }
            if let message = model.appHotKeyErrorMessage {
                SettingsErrorBanner(L10n.tr(message))
            }
        }
    }

    @ViewBuilder private var arrangementRows: some View {
        SettingsChoiceRow(
            L10n.tr("How should windows be arranged?"),
            isOn: $preferences.groupByApp,
            off: .init(L10n.tr("One grid"), detail: L10n.tr("See every window together.")),
            on: .init(L10n.tr("By app"), detail: L10n.tr("Keep each app’s windows together."))
        )
        SettingsDivider()
        SettingsRow(
            title: L10n.tr("Change layout while the overview is open"),
            subtitle: L10n.tr("Press this key to switch between one grid and groups.")
        ) {
            CharacterKeyRecorder(key: $preferences.groupToggleKey) { model.setHotKeyRecording($0) }
        }
        SettingsDivider()
        SettingsChoiceRow(
            L10n.tr("After moving a window to another workspace"),
            isOn: $preferences.followMovedWindow,
            off: .init(
                L10n.tr("Stay here"),
                detail: L10n.tr("Keep this overview open to organize more windows.")
            ),
            on: .init(
                L10n.tr("Go with the window"),
                detail: L10n.tr("Switch to its new workspace and close the overview.")
            )
        )
    }

    @ViewBuilder private var shortcutRows: some View {
        SettingsRow(
            title: L10n.tr("Find a window in this workspace"),
            subtitle: L10n.tr("See every window in the current workspace.")
        ) {
            HStack(spacing: 12) {
                HotKeyRecorder(
                    spec: $preferences.hotKey,
                    validate: { $0 != preferences.appHotKey },
                    onRecordingChanged: model.setHotKeyRecording
                )
                Button(L10n.tr("Try"), action: showOverview)
                    .accessibilityLabel(L10n.tr("Try Overview"))
            }
        }
        SettingsDivider()
        SettingsRow(
            title: L10n.tr("Find another window from the current app"),
            subtitle: L10n.tr("See this app’s windows across all workspaces.")
        ) {
            HStack(spacing: 12) {
                HotKeyRecorder(
                    spec: $preferences.appHotKey,
                    validate: { $0 != preferences.hotKey },
                    onRecordingChanged: model.setHotKeyRecording
                )
                Button(L10n.tr("Try"), action: showAppWindows)
                    .accessibilityLabel(L10n.tr("Try App Windows"))
            }
        }
    }
}

/// The overview demo bound to the live shortcut.
struct WindowOverviewDemoHost: View {
    @ObservedObject var preferences: ExposePreferences

    var body: some View {
        WindowOverviewDemo(shortcut: preferences.hotKey.displayKeys)
    }
}
