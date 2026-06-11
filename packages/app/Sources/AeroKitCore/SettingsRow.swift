import SwiftUI

public struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: LocalizedStringKey?
    @ViewBuilder let control: Control

    public init(title: String, subtitle: LocalizedStringKey? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    public var body: some View {
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

public struct SettingsToggle: View {
    @Binding var isOn: Bool
    var isEnabled = true

    public init(isOn: Binding<Bool>, isEnabled: Bool = true) {
        _isOn = isOn
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(!isEnabled)
    }
}

// MARK: - Keycaps

public struct KeyCapGroup: View {
    let keys: [String]
    var foreground = AnyShapeStyle(.primary.opacity(0.75))
    var background = AnyShapeStyle(.quaternary.opacity(0.7))

    public init(
        keys: [String],
        foreground: AnyShapeStyle = AnyShapeStyle(.primary.opacity(0.75)),
        background: AnyShapeStyle = AnyShapeStyle(.quaternary.opacity(0.7))
    ) {
        self.keys = keys
        self.foreground = foreground
        self.background = background
    }

    public var body: some View {
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

// MARK: - Section chrome

public struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)

            VStack(spacing: 0) { content }
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary.opacity(0.45))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
                }
        }
    }
}

public struct SettingsDivider: View {
    public init() {}

    public var body: some View {
        Divider()
            .opacity(0.5)
            .padding(.leading, 14)
    }
}

public struct SettingsErrorBanner: View {
    let message: String
    let icon: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(
        _ message: String,
        icon: String = "exclamationmark.triangle.fill",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.icon = icon
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Spacer()
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.orange.opacity(0.12))
        }
    }
}

// MARK: - Window backdrop

public struct SettingsBackdrop: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
