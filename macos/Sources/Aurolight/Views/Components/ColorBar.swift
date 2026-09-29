import AurolightCore
import SwiftUI

/// Every color at full value: hue runs left to right, saturation from white at the top to vivid at the bottom.
struct ColorBar: View {
    @Binding var color: RGB

    @State private var grayHue = 0.0
    @State private var isDragging = false

    private static let hues = Gradient(
        colors: stride(from: 0.0, through: 1, by: 1.0 / 12).map {
            Color(RGB(hue: $0, saturation: 1, value: 1))
        })
    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    private var hue: Double { color.saturation > 0 ? color.hue : grayHue }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Self.shape.fill(LinearGradient(gradient: Self.hues, startPoint: .leading, endPoint: .trailing))
                Self.shape.fill(
                    LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                Self.shape.strokeBorder(.white.opacity(0.18), lineWidth: 1)
                knob
                    .position(Self.position(hue: hue, saturation: color.saturation, in: size))
            }
            .contentShape(Self.shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        pick(value.location, in: size)
                    }
                    .onEnded { _ in isDragging = false })
        }
        .frame(width: 300, height: 40)
        .accessibilityElement()
        .accessibilityLabel("Color")
        .accessibilityValue(
            "Hue \(Int((hue * 360).rounded())) degrees, saturation \(Int((color.saturation * 100).rounded())) percent"
        )
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1.0 / 36 : -1.0 / 36
            let next = (hue + step + 1).truncatingRemainder(dividingBy: 1)
            color = RGB(hue: next, saturation: max(color.saturation, 0.5), value: 1)
        }
    }

    private var knob: some View {
        Circle()
            .fill(Color(color))
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .scaleEffect(isDragging ? 1.25 : 1)
            .animation(.snappy(duration: 0.15), value: isDragging)
    }

    private func pick(_ point: CGPoint, in size: CGSize) {
        color = Self.color(at: point, in: size)
        grayHue = min(max(point.x / size.width, 0), 1)
    }

    nonisolated static func color(at point: CGPoint, in size: CGSize) -> RGB {
        let hue = min(max(point.x / size.width, 0), 1)
        let saturation = min(max(point.y / size.height, 0), 1)
        return RGB(hue: hue == 1 ? 0 : hue, saturation: saturation, value: 1)
    }

    nonisolated static func position(hue: Double, saturation: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: hue * size.width, y: saturation * size.height)
    }
}
