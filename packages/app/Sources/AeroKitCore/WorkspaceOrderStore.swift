import Combine
import Foundation

private let log = AppLog(category: "core")

/// The user's workspace order, shared by the switcher grid and the swipe
/// ring. One instance lives in the app coordinator so the two settings
/// panes edit — and immediately see — the same arrangement.
@MainActor
public final class WorkspaceOrderStore: ObservableObject {
    /// Priority list applied through `WorkspaceOrdering`: listed names come
    /// first in this order, unlisted workspaces follow in natural order.
    @Published public var order: [String] {
        didSet {
            defaults.set(order, forKey: Self.key)
            if order != oldValue {
                log.notice("workspace order set: \(order.joined(separator: " → "))")
            }
        }
    }

    public static let defaultOrder = ["1", "2", "3", "4", "Q", "W", "E", "R"]

    private static let key = "workspace.order"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        order = defaults.stringArray(forKey: Self.key) ?? Self.defaultOrder
    }
}
