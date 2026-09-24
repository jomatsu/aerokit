import AeroKitCore

public enum SnapshotRefreshFeedback: Equatable {
    case idle
    case refreshing(completed: Int, total: Int)
    case success
    case failure(String)

    var isVisible: Bool {
        self != .idle
    }

    @MainActor var message: String {
        switch self {
        case .idle:
            ""
        case .refreshing:
            L10n.tr("Refreshing screenshots...")
        case .success:
            L10n.tr("Screenshots updated")
        case let .failure(message):
            message
        }
    }

    var progress: Double? {
        guard case let .refreshing(completed, total) = self, total > 0 else {
            return nil
        }
        return Double(completed) / Double(total)
    }
}
