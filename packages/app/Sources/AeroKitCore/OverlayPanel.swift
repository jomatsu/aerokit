import AppKit

/// Borderless, non-activating, screen-covering panel both overlays render
/// into: it becomes key without activating the app so keyboard input works
/// while the previous app keeps focus.
public final class OverlayPanel: NSPanel {
    /// Receives `keyDown` and ⌘-modified key-equivalent events alike.
    /// Return true to consume; note that returning false for a key
    /// equivalent can re-deliver the same event through `keyDown`.
    public var keyHandler: ((NSEvent) -> Bool)?
    public var onResignKey: (() -> Void)?

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override public var canBecomeKey: Bool {
        true
    }

    override public var canBecomeMain: Bool {
        false
    }

    override public func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    /// ⌘-modified keys arrive here instead of `keyDown`; route them to the
    /// same handler so overlays can bind key equivalents like ⌘W.
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override public func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Virtual key codes the overlays handle.
public enum KeyCode {
    public static let `return`: UInt16 = 36
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let escape: UInt16 = 53
    public static let keypadEnter: UInt16 = 76
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126
}
