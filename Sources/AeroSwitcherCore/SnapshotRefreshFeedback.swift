public enum SnapshotRefreshFeedback: Equatable {
    case idle
    case refreshing
    case success
    case failure(String)

    var isVisible: Bool {
        self != .idle
    }

    var message: String {
        switch self {
        case .idle:
            ""
        case .refreshing:
            "Refreshing screenshots..."
        case .success:
            "Screenshots updated"
        case let .failure(message):
            message
        }
    }
}
