import AurolightCore
import SwiftUI

struct BiasLightGlow: View {
    let layout: LEDLayout
    let colors: [RGB]
    let screen: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .named(ScreenRectKey.coordinateSpace)).origin
            canvas(screen: screen?.offsetBy(dx: -origin.x, dy: -origin.y))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func canvas(screen: CGRect?) -> some View {
        Canvas { context, _ in
            guard let screen, screen.width > 0 else { return }
            let slots = layout.slots()
            guard !slots.isEmpty, colors.count == slots.count else { return }
            let intensity = 0.4
            let reach = max(screen.width, screen.height) * 0.07
            let push = reach * 0.3

            let cluster = 3
            var groups: [(edge: ScreenEdge, position: Double, color: RGB, size: Int)] = []
            for (i, slot) in slots.enumerated() {
                if let last = groups.last, last.edge == slot.edge, last.size < cluster {
                    let n = Double(last.size)
                    groups[groups.count - 1] = (
                        slot.edge, (last.position * n + slot.position) / (n + 1),
                        RGB(
                            r: (last.color.r * n + colors[i].r) / (n + 1),
                            g: (last.color.g * n + colors[i].g) / (n + 1),
                            b: (last.color.b * n + colors[i].b) / (n + 1)), last.size + 1
                    )
                } else {
                    groups.append((slot.edge, slot.position, colors[i], 1))
                }
            }

            context.blendMode = .plusLighter
            for group in groups {
                let color = Color(group.color)
                let weight = Double(group.size)
                let origin = screen.point(on: group.edge, at: group.position, outset: push)
                let rect = CGRect(x: origin.x - reach, y: origin.y - reach, width: reach * 2, height: reach * 2)
                context.fill(
                    Ellipse().path(in: rect),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: color.opacity(min(intensity * weight, 1)), location: 0),
                            .init(color: color.opacity(min(intensity * 0.35 * weight, 1)), location: 0.45),
                            .init(color: color.opacity(0), location: 1),
                        ]),
                        center: origin, startRadius: 0, endRadius: reach))
            }
        }
    }
}

struct LiveBiasLightGlow: View {
    let layout: LEDLayout
    let live: LivePreview
    let screen: CGRect?

    var body: some View {
        BiasLightGlow(layout: layout, colors: live.colors, screen: screen)
    }
}
