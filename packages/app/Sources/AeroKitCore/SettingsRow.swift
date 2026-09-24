import SwiftUI

public extension EnvironmentValues {
    @Entry var settingsControlLabel: String = "Setting"
}

public struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let control: Control

    public init(title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 24) {
            SettingsRowLabel(title: title, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            control
                .environment(\.settingsControlLabel, title)
        }
        .padding(16)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .medium))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

public struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    let isEnabled: Bool

    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(title: title, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEnabled {
                        isOn.toggle()
                    }
                }
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .accessibilityLabel(title)
        .disabled(!isEnabled)
        .padding(16)
    }
}

public struct SettingsToggle: View {
    @Environment(\.settingsControlLabel)
    private var label
    @Binding var isOn: Bool
    var isEnabled = true

    public init(isOn: Binding<Bool>, isEnabled: Bool = true) {
        _isOn = isOn
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(label)
            .disabled(!isEnabled)
    }
}

public struct KeyCapGroup: View {
    let keys: [String]
    var foreground = AnyShapeStyle(.primary.opacity(0.85))
    var background = AnyShapeStyle(.quaternary.opacity(0.7))

    public init(
        keys: [String],
        foreground: AnyShapeStyle = AnyShapeStyle(.primary.opacity(0.85)),
        background: AnyShapeStyle = AnyShapeStyle(.quaternary.opacity(0.7))
    ) {
        self.keys = keys
        self.foreground = foreground
        self.background = background
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(foreground)
                    .frame(minWidth: 22, minHeight: 24)
                    .padding(.horizontal, key.count > 1 ? 5 : 1)
                    .background(background, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

public struct SettingsSection<Content: View, Accessory: View>: View {
    let title: String
    let accessory: Accessory
    @ViewBuilder let content: Content

    /// `accessory` sits right after the title, e.g. a `FeatureInfoButton`.
    public init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                accessory
            }
            .padding(.leading, 2)
            VStack(spacing: 0) { content }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
                }
        }
    }
}

public extension SettingsSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content) { EmptyView() }
    }
}

public struct SettingsDivider: View {
    public init() {}
    public var body: some View {
        Divider().padding(.horizontal, 16)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.orange).padding(.top, 2)
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(16)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

public struct SettingsBackdrop: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
