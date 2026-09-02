import Foundation

/// The key a cycling keystroke carries, resolved from the raw event before
/// any decision is made — the pure, unit-tested half of the window
/// switcher's key handling.
public enum CycleKeyInput: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The recorded trigger key itself (Tab by default).
        case hotKey
        case leftArrow
        case rightArrow
        case escape
        /// Anything else.
        case other
    }

    /// A keyDown/keyUp of some key.
    case key(Kind, shifted: Bool)
    /// A flagsChanged: did the trigger modifiers remain held afterwards?
    case modifiersChanged(triggerHeld: Bool)
}

/// What the key router should do with a keystroke while the strip is up.
public enum CycleAction: Equatable, Sendable {
    case advance
    case retreat
    case cancel
    case commit
    /// Consume so nothing types into the frontmost app.
    case swallow
    /// Deliver untouched — modifier state is never eaten.
    case pass
}

/// macOS ⌘Tab semantics, as pure rules: the trigger key advances (⇧
/// reverses), arrows move, Esc cancels, everything else is swallowed while
/// the strip is open, and dropping the trigger modifiers commits without
/// consuming the flagsChanged.
public enum CycleKeyRules {
    public static func action(for input: CycleKeyInput) -> CycleAction {
        switch input {
        case let .modifiersChanged(triggerHeld):
            triggerHeld ? .pass : .commit
        case let .key(kind, shifted):
            switch kind {
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
}
