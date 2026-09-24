import AppKit
import SwiftUI

public struct KeyRecorderButton: View {
    @Environment(\.settingsControlLabel)
    private var label
    @ObservedObject private var session = KeyRecordingSession.shared
    @State private var id = UUID()
    @State private var hitArea = RecorderHitArea()
    let keys: [String]
    let prompt: String
    let helpText: String
    let onRecordingChanged: (Bool) -> Void
    let record: (NSEvent) -> String?

    public init(
        keys: [String],
        prompt: String,
        helpText: String,
        onRecordingChanged: @escaping (Bool) -> Void,
        record: @escaping (NSEvent) -> String?
    ) {
        self.keys = keys
        self.prompt = prompt
        self.helpText = helpText
        self.onRecordingChanged = onRecordingChanged
        self.record = record
    }

    private var isRecording: Bool {
        session.activeID == id
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button(action: toggleRecording) {
                HStack(spacing: 10) {
                    if isRecording {
                        Image(systemName: "keyboard")
                        Text(prompt).font(.system(size: 12, weight: .medium))
                        Image(systemName: "xmark.circle.fill").accessibilityHidden(true)
                    } else if keys.isEmpty {
                        Text(L10n.tr("Set Shortcut…")).font(.system(size: 12))
                    } else {
                        KeyCapGroup(keys: keys)
                        Text(L10n.tr("Change…")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                .background(
                    isRecording ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.12))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .buttonStyle(.plain)
            .background(RecorderRegion(view: hitArea))
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isRecording ? L10n.tr("Waiting for a shortcut") : keys.joined(separator: " "))
            .help(helpText)

            if isRecording {
                Text(session.errorMessage ?? L10n.tr("\(helpText) · Esc to cancel"))
                    .font(.system(size: 12))
                    .foregroundStyle(session.errorMessage == nil ? Color.secondary : Color.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 250, alignment: .trailing)
            }
        }
        .onDisappear { session.stop(id: id) }
    }

    private var accessibilityLabel: String {
        if isRecording {
            L10n.tr("Cancel recording \(label)")
        } else if keys.isEmpty {
            L10n.tr("Set \(label) shortcut")
        } else {
            L10n.tr("Change \(label) shortcut")
        }
    }

    private func toggleRecording() {
        if isRecording {
            session.stop(id: id)
        } else {
            session.start(
                id: id,
                containsClick: { [weak hitArea] event in
                    guard let hitArea, event.window === hitArea.window else { return false }
                    return hitArea.bounds.contains(hitArea.convert(event.locationInWindow, from: nil))
                },
                onRecordingChanged: onRecordingChanged,
                record: record
            )
        }
    }
}

private final class RecorderHitArea: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct RecorderRegion: NSViewRepresentable {
    let view: RecorderHitArea
    func makeNSView(context: Context) -> RecorderHitArea {
        view
    }

    func updateNSView(_ nsView: RecorderHitArea, context: Context) {}
}
