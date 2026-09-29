import AurolightCore
import SwiftUI

struct LayoutStep: View {
    @Binding var layout: LEDLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(
                symbol: "light.strip.2",
                title: "Set up your strip",
                message:
                    "Count the LEDs along each edge of the screen. Leave an edge at 0 if the strip doesn't run there.")

            VStack(spacing: 10) {
                edge("Top", $layout.top, axis: .horizontal)
                HStack(spacing: 14) {
                    edge("Left", $layout.left, axis: .vertical)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(0.15))
                        }
                        .overlay {
                            Text("\(layout.placedCount) LEDs")
                                .font(.system(size: 26, weight: .thin))
                                .contentTransition(.numericText())
                        }
                        .frame(width: 250, height: 140)
                    edge("Right", $layout.right, axis: .vertical)
                }
                edge("Bottom", $layout.bottom, axis: .horizontal)
            }
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.2), value: layout.placedCount)

            Text(
                """
                You can set where the strip starts later, right on the preview. Black bars in videos are skipped \
                automatically.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func edge(_ title: String, _ value: Binding<Int>, axis: Axis) -> some View {
        CountControl(title: title, value: value, axis: axis)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}
