import AppKit
import SwiftUI

/// Shared chrome and capture lifecycle for the settings key recorders: a
/// keycap button that pulses while recording and feeds key-downs to the
/// caller. Escape cancels; a rejected key beeps and recording continues.
public struct KeyRecorderButton: View {
    let keys: [String]
    let prompt: String
    let helpText: String
    let onRecordingChanged: (Bool) -> Void
    /// Returns true when the event was accepted and recording should stop.
    let record: (NSEvent) -> Bool

    public init(
        keys: [String],
        prompt: String,
        helpText: String,
        onRecordingChanged: @escaping (Bool) -> Void,
        record: @escaping (NSEvent) -> Bool
    ) {
        self.keys = keys
        self.prompt = prompt
        self.helpText = helpText
        self.onRecordingChanged = onRecordingChanged
        self.record = record
    }

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pulse = false

    public var body: some View {
        Button(action: toggleRecording) {
            Group {
                if isRecording {
                    Text(prompt)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .opacity(pulse ? 0.45 : 1)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                        .onAppear {
                            pulse = true
                        }
                        .onDisappear {
                            pulse = false
                        }
                } else {
                    KeyCapGroup(keys: keys)
                }
            }
            .frame(minWidth: 76)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(.quaternary.opacity(isRecording ? 0.25 : 0.4))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .strokeBorder(
                        isRecording ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.2),
                        lineWidth: isRecording ? 1.5 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        onRecordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == KeyCode.escape {
                stopRecording()
            } else if record(event) {
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard isRecording else {
            return
        }
        isRecording = false
        onRecordingChanged(false)
    }
}
