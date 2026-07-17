import Foundation

/// One chip in the workspace order editor: the workspace and, when the
/// AeroSpace config binds a key combo to it, that combo for display.
public struct WorkspaceOrderEntry: Equatable, Sendable {
    public let name: String
    /// AeroSpace combo like "alt-1"; nil when no binding switches here.
    public let keyBinding: String?

    public init(name: String, keyBinding: String? = nil) {
        self.name = name
        self.keyBinding = keyBinding
    }
}

public extension AeroSpaceClient {
    /// Existing workspaces paired with the key combos that switch to them.
    /// Binding lookup failures degrade to names only — the order editor
    /// stays usable without them.
    func workspaceOrderEntries() throws -> [WorkspaceOrderEntry] {
        let names = try listWorkspaces().map(\.name)
        let bindings = (try? workspaceKeyBindings()) ?? [:]
        return names.map { WorkspaceOrderEntry(name: $0, keyBinding: bindings[$0]) }
    }
}

/// Renders AeroSpace key combos with macOS modifier symbols:
/// "alt-shift-1" becomes "⌥⇧1".
public enum KeyComboDisplay {
    public static func symbols(_ combo: String) -> String {
        combo
            .split(separator: "-")
            .map { token in
                let token = String(token)
                return modifierSymbol(token) ?? keyLabel(token)
            }
            .joined()
    }

    private static func modifierSymbol(_ token: String) -> String? {
        switch token.lowercased() {
        case "alt", "lalt", "ralt", "opt", "option": "⌥"
        case "cmd", "lcmd", "rcmd", "command": "⌘"
        case "ctrl", "lctrl", "rctrl", "control": "⌃"
        case "shift", "lshift", "rshift": "⇧"
        default: nil
        }
    }

    private static func keyLabel(_ token: String) -> String {
        switch token.lowercased() {
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        case "tab": "⇥"
        case "enter": "⏎"
        case "esc": "⎋"
        case "space": "␣"
        default: token.count == 1 ? token.uppercased() : token
        }
    }
}
