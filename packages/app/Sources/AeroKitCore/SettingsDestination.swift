import SwiftUI

public enum SettingsDestination: String, CaseIterable, Identifiable {
    case general = "General"
    case workspaces = "Workspaces"
    case windows = "Windows"
    case previews = "Preview Images"

    public var id: String {
        rawValue
    }

    @MainActor public var title: String {
        switch self {
        case .general: L10n.tr("General")
        case .workspaces: L10n.tr("Workspaces")
        case .windows: L10n.tr("Windows")
        case .previews: L10n.tr("Preview Images")
        }
    }

    public var icon: String {
        switch self {
        case .general: "gearshape"
        case .workspaces: "square.grid.2x2"
        case .windows: "macwindow.on.rectangle"
        case .previews: "photo.on.rectangle"
        }
    }
}

public extension EnvironmentValues {
    @Entry var openSettingsDestination: @MainActor (SettingsDestination) -> Void = { _ in }
}
