import AeroKitCore
import SwiftUI

struct SwipeDistanceControl: View {
    @Binding var distance: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("How far to swipe for one workspace")).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(L10n.tr("\(Int(distance)) mm"))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text(L10n.tr("Short"))
                Slider(value: $distance, in: SwipePreferences.stepDistanceRange, step: 5)
                    .accessibilityLabel(L10n.tr("Finger travel in millimeters per workspace"))
                    .accessibilityValue(L10n.tr("\(Int(distance)) mm"))
                Text(L10n.tr("Long"))
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            Text(L10n.tr("Short swipes need less finger travel. Long swipes help avoid switching too easily."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(16)
    }
}
