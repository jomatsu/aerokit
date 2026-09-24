import AeroKitCore
import SwiftUI

/// One settings destination: its header with a page-scoped reset, then the
/// feature sections that belong to it. Copy stays a resource until the body
/// runs, so a language change re-renders it.
struct SettingsPage<Content: View>: View {
    let destination: SettingsDestination
    let subtitle: LocalizedStringResource
    let resetMessage: LocalizedStringResource
    let onReset: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsPageHeader(
                destination.title,
                subtitle: L10n.tr(subtitle),
                resetMessage: L10n.tr(resetMessage),
                onReset: onReset
            )
            content
        }
    }
}
