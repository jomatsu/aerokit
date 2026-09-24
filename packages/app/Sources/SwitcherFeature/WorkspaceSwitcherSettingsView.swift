import AeroKitCore
import SwiftUI

/// The workspace grid's whole setup in one section: how it opens, what it
/// selects, when it commits, and how it looks.
struct WorkspaceSwitcherSettingsView: View {
    @ObservedObject var model: SwitcherSettingsModel
    @ObservedObject var preferences: AppPreferences

    init(model: SwitcherSettingsModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(L10n.tr("Workspace switcher")) {
                shortcutRow
                SettingsDivider()
                selectionRows
                SettingsDivider()
                layoutRows
            } accessory: {
                FeatureInfoButton(L10n.tr("Workspace switcher")) {
                    WorkspaceSwitcherDemoHost(preferences: preferences)
                }
            }
            if let message = model.hotKeyErrorMessage {
                SettingsErrorBanner(L10n.tr(message))
            }
        }
        .onAppear { model.refreshStatus() }
    }

    @ViewBuilder private var selectionRows: some View {
        SettingsChoiceRow(
            L10n.tr("Which workspace is highlighted first?"),
            isOn: $preferences.preselectNextOnOpen,
            off: .init(
                L10n.tr("The current one"),
                detail: L10n.tr("Start where you are. Move to another workspace yourself.")
            ),
            on: .init(
                L10n.tr("The next one"),
                detail: L10n.tr("Start one step ahead in your workspace order.")
            )
        )
        SettingsDivider()
        SettingsChoiceRow(
            L10n.tr("When should the switch happen?"),
            isOn: $preferences.switchOnRelease,
            off: .init(
                L10n.tr("Press Return"),
                detail: L10n.tr("Browse freely. Press ↵ when you’re ready to switch.")
            ),
            on: .init(
                L10n.tr("Release \(heldKeys)"),
                detail: L10n.tr("Keep \(heldKeys) held while choosing. Let go to switch.")
            )
        )
    }

    @ViewBuilder private var layoutRows: some View {
        SettingsRow(
            title: L10n.tr("Workspaces per row"),
            subtitle: L10n.tr("Fewer per row makes each preview larger.")
        ) {
            GridLayoutPicker(selection: $preferences.gridColumns, range: 2 ... 6)
        }
        SettingsDivider()
        SettingsToggleRow(
            L10n.tr("Include empty workspaces"),
            subtitle: L10n.tr("Empty workspaces appear too, so you can switch to a fresh space."),
            isOn: Binding(
                get: { !preferences.hideEmptyWorkspaces },
                set: { preferences.hideEmptyWorkspaces = !$0 }
            )
        )
    }

    private var shortcutRow: some View {
        SettingsRow(
            title: L10n.tr("Show all workspaces"),
            subtitle: L10n.tr("Choose with the arrow keys. Add ⇧ to the shortcut to go back.")
        ) {
            HStack(spacing: 12) {
                HotKeyRecorder(
                    spec: $preferences.hotKey,
                    // The in-switcher shortcuts are fixed; the opening
                    // shortcut must not shadow them.
                    validate: { candidate in
                        [preferences.refreshShortcut, preferences.settingsShortcut].allSatisfy {
                            $0.keyCode != candidate.keyCode || $0.modifierFlags != candidate.modifierFlags
                        }
                    },
                    onRecordingChanged: model.setHotKeyRecording
                )
                Button(L10n.tr("Try")) { model.onShowSwitcher?() }
                    .accessibilityLabel(L10n.tr("Try Switcher"))
            }
        }
    }

    private var heldKeys: String {
        preferences.hotKey.displayKeys.dropLast().joined(separator: " + ")
    }
}

/// The one place to edit the order shared by the grid and swipes.
struct WorkspaceOrderSettingsView: View {
    @ObservedObject var model: SwitcherSettingsModel

    var body: some View {
        SettingsSection(L10n.tr("Workspace order")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("Drag to reorder, or right-click a workspace to move it."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                WorkspaceOrderEditor(store: model.workspaceOrder, loadWorkspaces: model.loadWorkspaces)
            }.padding(16)
        }
    }
}

/// The grid demo bound to the live preferences.
struct WorkspaceSwitcherDemoHost: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        WorkspaceSwitcherDemo(
            shortcut: preferences.hotKey.displayKeys,
            releaseToSwitch: preferences.switchOnRelease,
            startsOnNext: preferences.preselectNextOnOpen
        )
    }
}
