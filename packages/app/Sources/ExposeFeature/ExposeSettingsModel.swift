import AeroKitCore
import SwiftUI

private let log = AppLog(category: "expose")

@MainActor
final class ExposeSettingsModel: ObservableObject {
    @Published var hotKeyErrorMessage: LocalizedStringResource?
    @Published var appHotKeyErrorMessage: LocalizedStringResource?
    @Published var swipeErrorMessage: LocalizedStringResource?
    @Published var systemGestureErrorMessage: LocalizedStringResource?

    /// Mirror of the macOS Mission Control / App Exposé gesture checkboxes;
    /// refreshed whenever the pane (re)appears because System Settings can
    /// change them behind our back.
    @Published var systemGesturesEnabled = SystemSwipeGestures.isEnabled

    var onHotKeyRecordingChanged: ((Bool) -> Void)?

    /// Chained so rapid toggling cannot interleave two write-and-restart
    /// sequences and leave the system disagreeing with the toggle.
    private var systemGestureWrite: Task<Void, Never>?

    func refreshSystemGestures() {
        systemGesturesEnabled = SystemSwipeGestures.isEnabled
    }

    /// Optimistically flips the toggle, then writes the Dock preferences
    /// and restarts the Dock off-main; a failure resyncs from the system.
    func setSystemGestures(_ enabled: Bool) {
        systemGesturesEnabled = enabled
        systemGestureErrorMessage = nil
        systemGestureWrite = Task.detached(priority: .userInitiated) { [previousWrite = systemGestureWrite] in
            await previousWrite?.value
            do {
                try SystemSwipeGestures.setEnabled(enabled)
            } catch {
                log.error("updating system swipe gestures failed: \(error)")
                await MainActor.run {
                    self.systemGestureErrorMessage = "Could not change the system swipe gestures."
                    self.refreshSystemGestures()
                }
            }
        }
    }

    /// Counted because the pane has one recorder per hotkey and the user can
    /// start the second before finishing the first; the global triggers must
    /// stay suspended until no recorder is active.
    private var activeRecorders = 0

    func setHotKeyRecording(_ isRecording: Bool) {
        let wasRecording = activeRecorders > 0
        activeRecorders = max(0, activeRecorders + (isRecording ? 1 : -1))
        let isRecordingNow = activeRecorders > 0
        if wasRecording != isRecordingNow {
            onHotKeyRecordingChanged?(isRecordingNow)
        }
    }
}
