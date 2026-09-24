import AeroKitCore
import SwiftUI

struct PreviewSettingsView: View {
    @ObservedObject var model: SwitcherSettingsModel
    @ObservedObject var preferences: AppPreferences
    @Environment(\.openSettingsDestination)
    private var openPage
    @State private var sheet: Sheet?
    @State private var confirmingDelete = false

    private enum Sheet: String, Identifiable {
        case applications
        var id: String {
            rawValue
        }
    }

    init(model: SwitcherSettingsModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsPageHeader(
                SettingsDestination.previews.title,
                subtitle: L10n.tr(
                    "Previews are local images of your windows. Choose how they update and which apps to leave out."
                ),
                resetMessage: L10n.tr("""
                Restore automatic updates and the default freshness. Excluded apps and saved \
                previews are kept.
                """)
            ) {
                preferences.resetPreviewSettings()
            }
            if !model.screenCaptureGranted {
                SettingsErrorBanner(
                    L10n.tr("Allow Screen Recording to capture window previews."),
                    actionTitle: L10n.tr("Review Permissions…")
                ) { openPage(.general) }
            }
            captureSection
            // A missing permission already has its own banner above; the
            // capture error it causes would only repeat it, unlocalized.
            if model.screenCaptureGranted, let error = model.lastErrorMessage {
                SettingsErrorBanner(error)
            }
            exclusionsSection
            storageSection
            if let error = model.deleteError {
                SettingsErrorBanner(error)
            }
        }
        .onAppear { model.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshStatus()
        }
        .sheet(item: $sheet) { _ in AppExclusionPicker(preferences: preferences) }
        .alert(L10n.tr("Delete saved previews?"), isPresented: $confirmingDelete) {
            Button(L10n.tr("Cancel"), role: .cancel) {}
            Button(L10n.tr("Delete Previews"), role: .destructive) { model.deleteSnapshots() }
        } message: {
            Text(
                L10n.tr("""
                All stored workspace images and window titles will be deleted. Automatic updates \
                will be turned off. You can capture new previews with Update Now.
                """)
            )
        }
    }

    private var captureSection: some View {
        SettingsSection(L10n.tr("Capture")) {
            SettingsChoiceRow(
                L10n.tr("Who updates the preview images?"),
                isOn: $preferences.autoRefresh,
                off: .init(
                    L10n.tr("I’ll update them"),
                    detail: L10n.tr("Keep saved images until I click Update Now.")
                ),
                on: .init(
                    L10n.tr("AeroKit updates them"),
                    detail: L10n.tr("Take new previews as I change workspaces.")
                )
            )
            .disabled(model.isDeletingSnapshots)
            if preferences.autoRefresh {
                SettingsDivider()
                freshnessRow
            }
            SettingsDivider()
            updateNowRow
        }
    }

    private var updateNowRow: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            SettingsRow(title: L10n.tr("Take new screenshots now"), subtitle: updatedText) {
                if model.isRefreshingSnapshots || model.isDeletingSnapshots {
                    ProgressView().controlSize(.small).accessibilityLabel(L10n.tr("Updating saved previews"))
                } else {
                    Button(L10n.tr("Update Now")) { model.refreshSnapshots() }
                        .disabled(!model.screenCaptureGranted)
                }
            }
        }
    }

    private var freshnessRow: some View {
        SettingsRow(
            title: L10n.tr("Refresh on opening if images are older than"),
            subtitle: L10n.tr("""
            Refresh older previews when the switcher opens. Workspace changes also refresh \
            them in the background.
            """)
        ) {
            Picker(
                L10n.tr("Maximum image age when opening the grid"),
                selection: $preferences.refreshFrequency
            ) {
                ForEach(SnapshotRefreshFrequency.allCases) { frequency in
                    Text(frequency == .every3Minutes ? L10n.tr("3 min (Default)") : frequency.shortLabel)
                        .tag(frequency)
                }
            }.labelsHidden().frame(width: 150)
        }
    }

    private var exclusionsSection: some View {
        SettingsSection(L10n.tr("Keep apps out of previews")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("\(preferences.snapshotExclusions.count) apps excluded"))
                            .font(.system(size: 13, weight: .medium))
                        Text(L10n.tr("Their windows are omitted from future saved workspace previews."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.tr("Choose Apps…")) { sheet = .applications }
                }
                if !preferences.snapshotExclusions.isEmpty {
                    ForEach(preferences.snapshotExclusions.sorted(), id: \.self) { token in
                        ExcludedAppRow(token: token) {
                            preferences.snapshotExcludedApps = preferences.snapshotExclusions
                                .subtracting([token]).sorted().joined(separator: ", ")
                        }
                    }
                    Text(L10n
                        .tr("This applies to new screenshots. Use Update Now to replace the images already saved."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(16)
        }
    }

    private var storageSection: some View {
        SettingsSection(L10n.tr("Storage")) {
            SettingsRow(
                title: L10n.tr("See the saved image files"),
                subtitle: L10n.tr("View the images and window titles stored by AeroKit.")
            ) {
                Button(L10n.tr("Open Folder…")) { model.openSnapshotFolder() }
            }
            SettingsDivider()
            SettingsRow(
                title: L10n.tr("Remove all saved screenshots"),
                subtitle: L10n.tr("Delete stored images and turn off automatic updates.")
            ) {
                Button(L10n.tr("Delete Previews…"), role: .destructive) { confirmingDelete = true }
                    .disabled(model.isDeletingSnapshots)
            }
        }
    }

    private var updatedText: String {
        if model.isDeletingSnapshots {
            return L10n.tr("Deleting previews…")
        }
        if model.isRefreshingSnapshots {
            if let progress = model.refreshProgress {
                return L10n.tr("Capturing \(progress.completed) of \(progress.total)…")
            }
            return L10n.tr("Capturing previews…")
        }
        if let date = model.snapshotModifiedAt {
            let relativeDate = date.formatted(
                .relative(presentation: .named).locale(LanguagePreferences.shared.selected.locale)
            )
            return L10n.tr("Updated \(relativeDate)")
        }
        return L10n.tr("No previews saved yet")
    }
}
