import AeroKitCore
import AppKit
import SwiftUI

struct AppExclusionPicker: View {
    @ObservedObject var preferences: AppPreferences
    @Environment(\.dismiss)
    private var dismiss
    @State private var applications: [ExclusionApplication] = []
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var customRule = ""
    @State private var loading = true
    @FocusState private var searchFocused: Bool

    private var unlistedSelections: [String] {
        let known = Set(applications.flatMap { [$0.id, $0.name.lowercased()] })
        return selected.subtracting(known).sorted()
    }

    private var filteredApps: [ExclusionApplication] {
        applications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.tr("Exclude apps from previews")).font(.system(size: 20, weight: .bold))
            Text(L10n.tr("Choose apps whose windows should never appear in future saved workspace previews."))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.tr("Search apps"), text: $query).textFieldStyle(.plain).focused($searchFocused)
            }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            appList
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Add an app name or bundle ID manually"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    TextField(L10n.tr("App name or bundle ID"), text: $customRule).onSubmit(addCustomRule)
                    Button(L10n.tr("Add"), action: addCustomRule)
                        .disabled(customRule.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            HStack {
                Text(L10n.tr("\(selected.count) selected")).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Save Exclusions")) {
                    preferences.snapshotExcludedApps = selected.sorted().joined(separator: ", ")
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(loading)
            }
        }
        .padding(24)
        .frame(width: 480, height: 540)
        .task {
            selected = preferences.snapshotExclusions
            applications = await BlockingWork.run { ExclusionApplication.installed() }
            loading = false
            searchFocused = true
        }
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if loading {
                    ProgressView(L10n.tr("Finding apps…")).frame(maxWidth: .infinity).padding(30)
                } else if filteredApps.isEmpty {
                    Text(L10n.tr("No apps match your search")).foregroundStyle(.secondary).padding(16)
                }
                ForEach(filteredApps) { app in
                    Toggle(isOn: Binding(
                        get: { selected.contains(app.id) || selected.contains(app.name.lowercased()) },
                        set: { enabled in
                            selected.remove(app.name.lowercased())
                            if enabled {
                                selected.insert(app.id)
                            } else {
                                selected.remove(app.id)
                            }
                        }
                    )) {
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .resizable().frame(width: 26, height: 26)
                            Text(app.name).font(.system(size: 13))
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(8)
                    .accessibilityLabel(L10n.tr("Exclude \(app.name) from saved previews"))
                }
                if !unlistedSelections.isEmpty {
                    Divider().padding(.vertical, 8)
                    Text(L10n.tr("Additional exclusions (\(unlistedSelections.count))"))
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(unlistedSelections, id: \.self) { token in
                        ExcludedAppRow(token: token) { selected.remove(token) }
                    }
                }
            }
        }.frame(maxHeight: .infinity)
    }

    private func addCustomRule() {
        let token = customRule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty else { return }
        let tokens = token.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        selected.formUnion(tokens.filter { !$0.isEmpty })
        customRule = ""
    }
}

struct ExcludedAppRow: View {
    let token: String
    let remove: () -> Void

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: token)
    }

    private var displayName: String {
        appURL
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ??
            token
    }

    var body: some View {
        HStack(spacing: 10) {
            if let url = appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: "app").font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 24)
            }
            Text(displayName).font(.system(size: 13)).lineLimit(1).help(token)
            Spacer()
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).accessibilityLabel(L10n.tr("Remove \(displayName) from excluded apps"))
        }.padding(.vertical, 3)
    }
}

struct ExclusionApplication: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL

    static func installed() -> [Self] {
        let manager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var apps: [String: Self] = [:]
        for root in roots {
            let directories = [root, root.appendingPathComponent("Utilities")]
            for directory in directories {
                let urls = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                for url in urls where url.pathExtension == "app" {
                    guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { continue }
                    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    apps[identifier.lowercased()] = Self(id: identifier.lowercased(), name: name, url: url)
                }
            }
        }
        return apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
