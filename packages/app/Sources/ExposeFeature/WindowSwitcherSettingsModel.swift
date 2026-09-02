import Foundation

/// Settings-pane state for the window switcher: the hotkey registration
/// error surfaced as a banner, and the recording flag that makes the
/// controller suspend its global triggers while the recorder is up.
@MainActor
public final class WindowSwitcherSettingsModel: ObservableObject {
    @Published public var hotKeyErrorMessage: String?
    @Published public var isRecording = false

    /// Set by the controller: global triggers suspend while a recorder is
    /// up, so the chosen combination reaches the recorder.
    public var onHotKeyRecordingChanged: ((Bool) -> Void)?

    public init() {}
}
