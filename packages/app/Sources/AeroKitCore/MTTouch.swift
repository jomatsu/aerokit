/// Memory layout of one touch as MultitouchSupport reports it, per the
/// community-documented ABI; only `state` and `normalized` are read.
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTReadout
    var total: Float
    var pressure: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTReadout
    var field14: Int32
    var field15: Int32
    var density: Float

    struct MTPoint {
        var horizontal: Float
        var vertical: Float
    }

    struct MTReadout {
        var position: MTPoint
        var velocity: MTPoint
    }

    /// Touch states 3 (make touch) and 4 (touching) mean the finger is on
    /// the pad; lower values are hover, higher values are lift-off.
    var isTouching: Bool {
        state == 3 || state == 4
    }
}
