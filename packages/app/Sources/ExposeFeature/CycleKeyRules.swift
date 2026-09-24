import Foundation

/// Keys handled by the window cycling panel.
public enum CycleKeyInput: Equatable, Sendable {
    /// The configured trigger key itself.
    case hotKey
    case leftArrow
    case rightArrow
    case escape
    case other
}

public enum CycleAction: Equatable, Sendable {
    case advance
    case retreat
    case cancel
    case swallow
}

/// The trigger key advances, Shift reverses, arrows move, and Escape cancels.
/// Modifier release is handled separately by HoldToCommitDismiss.
public enum CycleKeyRules {
    public static func action(for key: CycleKeyInput, shifted: Bool = false) -> CycleAction {
        switch key {
        case .hotKey:
            shifted ? .retreat : .advance
        case .leftArrow:
            .retreat
        case .rightArrow:
            .advance
        case .escape:
            .cancel
        case .other:
            .swallow
        }
    }
}
