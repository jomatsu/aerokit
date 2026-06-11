import Carbon
import SwiftUI

struct HotKeyRecorder: View {
    @Binding var spec: HotKeySpec
    var validate: (HotKeySpec) -> Bool = { _ in true }
    let onRecordingChanged: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pulse = false

    var body: some View {
        Button(action: toggleRecording) {
            Group {
                if isRecording {
                    Text("Recording…")
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
                    KeyCapGroup(keys: spec.displayKeys)
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
        .help("Click, then press a key combination with ⌃, ⌥ or ⌘")
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
            if event.keyCode == UInt16(kVK_Escape) { // Escape cancels recording
                stopRecording()
                return nil
            }
            guard let recorded = HotKeySpec.from(event: event), validate(recorded) else {
                NSSound.beep()
                return nil
            }
            spec = recorded
            stopRecording()
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
