import SwiftUI

public struct SettingsPageHeader: View {
    let title: String
    let subtitle: String
    let resetMessage: String
    let onReset: (() -> Void)?
    @State private var confirmingReset = false

    public init(
        _ title: String,
        subtitle: String,
        resetMessage: String =
            L10n
                .tr(
                    "Restore the options on this page to their original values. Saved previews and macOS permissions are kept."
                ),
        onReset: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onReset = onReset
        self.resetMessage = resetMessage
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 26, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if onReset != nil {
                Button(L10n.tr("Reset…")) { confirmingReset = true }
                    .help(L10n.tr("Restore \(title) settings to their defaults"))
                    .accessibilityLabel(L10n.tr("Reset \(title) settings"))
            }
        }
        .padding(.bottom, 4)
        .alert(L10n.tr("Reset \(title) settings?"), isPresented: $confirmingReset) {
            Button(L10n.tr("Cancel"), role: .cancel) {}
            Button(L10n.tr("Reset to Defaults")) { onReset?() }
        } message: {
            Text(resetMessage)
        }
    }
}

public struct SettingsStatus: View {
    let title: String
    let ready: Bool

    public init(_ title: String, ready: Bool) {
        self.title = title
        self.ready = ready
    }

    public var body: some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ready ? Color.green : Color.orange)
            .fixedSize()
    }
}
