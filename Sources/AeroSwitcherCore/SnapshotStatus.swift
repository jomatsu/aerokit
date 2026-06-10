public enum SnapshotStatus: String, Sendable {
    case captured
    case cached
    case capturedVisible = "captured-visible"
    case failed
    case failedBlack = "failed-black"

    public var isUsable: Bool {
        switch self {
        case .captured, .cached, .capturedVisible:
            true
        case .failed, .failedBlack:
            false
        }
    }
}
