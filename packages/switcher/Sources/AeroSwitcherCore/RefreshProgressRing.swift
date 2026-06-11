import SwiftUI

struct RefreshProgressRing: View {
    /// nil renders an indeterminate spinning arc.
    var progress: Double?

    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: progress.map { max(0.02, $0) } ?? 0.3)
                .stroke(
                    AngularGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(isSpinning && progress == nil ? 270 : -90))
                .animation(
                    progress == nil
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .easeOut(duration: 0.25),
                    value: isSpinning
                )
                .animation(.easeOut(duration: 0.25), value: progress)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            isSpinning = true
        }
    }
}
