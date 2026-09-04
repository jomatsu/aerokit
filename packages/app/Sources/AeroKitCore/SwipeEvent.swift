/// The axis a three-finger gesture locked onto.
public enum SwipeAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

/// Lifecycle of one three-finger gesture, in `NSEvent.trackSwipeEvent`
/// style: progress follows the fingers continuously and the outcome is
/// decided when they lift, so a swipe pulled back before release cancels.
public enum SwipeEvent: Equatable, Sendable {
    /// The gesture's travel picked an axis; `moved` events follow.
    case began(SwipeAxis)
    /// Signed progress along the locked axis: +1.0 is the travel a slow
    /// swipe needs to commit one step, toward the right or top of the pad.
    case moved(SwipeAxis, progress: Float)
    /// The fingers lifted. `steps` is the committed step count (negative
    /// means left or down); 0 means the gesture cancelled — pulled back or
    /// too short.
    case ended(SwipeAxis, steps: Int)

    public var axis: SwipeAxis {
        switch self {
        case let .began(axis), let .moved(axis, _), let .ended(axis, _):
            axis
        }
    }
}
