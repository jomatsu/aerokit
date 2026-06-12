import Combine
import Foundation

@MainActor
public final class SwipePreferences: ObservableObject {
    /// Three-finger horizontal swipes switch AeroSpace workspaces.
    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    /// Content follows the fingers: swiping left moves to the workspace on
    /// the right, matching how scrolling feels.
    @Published public var naturalDirection: Bool {
        didSet { defaults.set(naturalDirection, forKey: Keys.naturalDirection) }
    }

    /// Swiping past the last workspace lands on the first and vice versa.
    @Published public var wrapAround: Bool {
        didSet { defaults.set(wrapAround, forKey: Keys.wrapAround) }
    }

    /// Step over workspaces that have no windows.
    @Published public var skipEmpty: Bool {
        didSet { defaults.set(skipEmpty, forKey: Keys.skipEmpty) }
    }

    /// Show the workspace strip HUD after every switch.
    @Published public var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Keys.showHUD) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabled = "swipe.enabled"
        static let naturalDirection = "swipe.naturalDirection"
        static let wrapAround = "swipe.wrapAround"
        static let skipEmpty = "swipe.skipEmpty"
        static let showHUD = "swipe.showHUD"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        naturalDirection = defaults.object(forKey: Keys.naturalDirection) as? Bool ?? true
        wrapAround = defaults.object(forKey: Keys.wrapAround) as? Bool ?? true
        skipEmpty = defaults.object(forKey: Keys.skipEmpty) as? Bool ?? true
        showHUD = defaults.object(forKey: Keys.showHUD) as? Bool ?? true
    }
}
