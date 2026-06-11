import SwiftUI

struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: LocalizedStringKey?
    @ViewBuilder let control: Control

    init(title: String, subtitle: LocalizedStringKey? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 16)

            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Toggle

struct SettingsToggle: View {
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(!isEnabled)
    }
}

// MARK: - Keycaps

struct KeyCapGroup: View {
    let keys: [String]
    var foreground = AnyShapeStyle(.primary.opacity(0.75))
    var background = AnyShapeStyle(.quaternary.opacity(0.7))

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(foreground)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, key.count > 1 ? 4 : 0)
                    .background {
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(background)
                    }
            }
        }
    }
}

// MARK: - Window backdrop

struct SettingsBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
