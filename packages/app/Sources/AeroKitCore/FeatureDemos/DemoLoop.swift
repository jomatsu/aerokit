import SwiftUI

// Looping, drawn feature demos for the settings (i) popovers and the
// welcome tour. They depict AeroSpace as it is — tiled windows, one
// layout per workspace — and play the user's own shortcuts.

/// Plays `content` with a progress value that runs 0 → 1 every `duration`
/// seconds and loops. With Reduce Motion the demo holds `stillFrame`.
public struct DemoLoop<Content: View>: View {
    let duration: Double
    let stillFrame: Double
    let content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.demoProgressOverride)
    private var progressOverride
    @State private var origin = Date()

    public init(duration: Double, stillFrame: Double, @ViewBuilder content: @escaping (Double) -> Content) {
        self.duration = duration
        self.stillFrame = stillFrame
        self.content = content
    }

    public var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 60,
            paused: reduceMotion || progressOverride != nil
        )) { context in
            content(progressOverride ?? (reduceMotion ? stillFrame : phase(at: context.date)))
        }
        .onAppear { origin = .now }
    }

    private func phase(at date: Date) -> Double {
        (date.timeIntervalSince(origin) / duration).truncatingRemainder(dividingBy: 1)
    }
}

public extension EnvironmentValues {
    /// Pins every `DemoLoop` to one frame; used to render demos in tests.
    @Entry var demoProgressOverride: Double?
}

/// Curves and key-timing helpers; every demo is a pure function of progress.
public enum DemoTiming {
    static func unit(_ progress: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (progress - start) / (end - start)))
    }

    /// Ease in-out (cubic) from 0 at `start` to 1 at `end`.
    public static func ease(_ progress: Double, from start: Double, to end: Double) -> Double {
        let value = unit(progress, start, end)
        return value < 0.5 ? 4 * value * value * value : 1 - pow(-2 * value + 2, 3) / 2
    }

    /// Fast out with a small overshoot, for things that settle into place.
    public static func settle(_ progress: Double, from start: Double, to end: Double) -> Double {
        let value = unit(progress, start, end)
        guard value > 0 else { return 0 }
        let overshoot = 1.25
        return 1 + (overshoot + 1) * pow(value - 1, 3) + overshoot * pow(value - 1, 2)
    }

    public static func during(_ progress: Double, _ start: Double, _ end: Double) -> Bool {
        progress >= start && progress < end
    }

    /// A key press lasting a moment after `time`.
    public static func tap(_ progress: Double, at time: Double) -> Bool {
        during(progress, time, time + 0.03)
    }

    public static func count(_ progress: Double, _ times: [Double]) -> Int {
        times.filter { progress >= $0 }.count
    }

    public static func mix(_ from: CGFloat, _ to: CGFloat, _ amount: Double) -> CGFloat {
        from + (to - from) * CGFloat(amount)
    }

    public static func mix(_ from: CGRect, _ to: CGRect, _ amount: Double) -> CGRect {
        CGRect(
            x: mix(from.minX, to.minX, amount),
            y: mix(from.minY, to.minY, amount),
            width: mix(from.width, to.width, amount),
            height: mix(from.height, to.height, amount)
        )
    }
}
