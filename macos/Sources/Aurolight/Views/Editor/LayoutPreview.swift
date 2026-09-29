import AurolightCore
import SwiftUI

struct LayoutPreview: View {
    let layout: LEDLayout
    let colors: [RGB]
    let geometry: PreviewGeometry
    var screenImage: CGImage?

    var body: some View {
        ZStack {
            MonitorArtwork(screen: geometry.screen)
            liveCanvas
        }
    }

    private var liveCanvas: some View {
        Canvas { context, _ in
            let screen = geometry.screen
            let slots = layout.slots()
            let live = colors.count == slots.count && !slots.isEmpty

            let panel = RoundedRectangle(cornerRadius: 6).path(in: screen)
            context.drawLayer { layer in
                layer.clip(to: panel)
                if let screenImage {
                    layer.draw(Image(decorative: screenImage, scale: 1), in: screen)
                    var ignored = Path(screen)
                    ignored.addPath(Path(geometry.region(layout.detectionArea)))
                    layer.fill(ignored, with: .color(.black.opacity(0.78)), style: FillStyle(eoFill: true))
                } else if live {
                    for (i, slot) in slots.enumerated() {
                        layer.fill(Path(geometry.region(slot.region)), with: .color(Color(colors[i]).opacity(0.75)))
                    }
                }
                layer.fill(
                    panel,
                    with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.06), .white.opacity(0)]),
                        startPoint: CGPoint(x: screen.minX, y: screen.minY),
                        endPoint: CGPoint(x: screen.midX, y: screen.midY)))
            }

            drawDiodes(in: &context, slots: slots, live: live)
        }
    }

    private func drawDiodes(in context: inout GraphicsContext, slots: [LEDSlot], live: Bool) {
        let radius = diodeRadius()
        let last = slots.count - 1
        for (i, slot) in slots.enumerated() where i != 0 && i != last {
            let p = geometry.ledPoint(for: slot)
            context.fill(
                Circle().path(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(live ? Color(colors[i]) : .white.opacity(0.22)))
        }
        guard let first = slots.first else { return }

        func marker(_ slot: LEDSlot, _ color: Color) {
            let p = geometry.ledPoint(for: slot)
            let dot = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Circle().path(in: dot), with: .color(color))
            context.stroke(
                Circle().path(in: dot.insetBy(dx: -2.5, dy: -2.5)), with: .color(color.opacity(0.7)), lineWidth: 1.2)
        }
        if last > 0 { marker(slots[last], .red) }
        marker(first, .green)

        if slots.count > 1 {
            let p = geometry.ledPoint(for: first), q = geometry.ledPoint(for: slots[1])
            let center = geometry.ledPoint(for: first, gap: PreviewGeometry.ledGap + radius + 9)
            let angle = atan2(q.y - p.y, q.x - p.x)
            var chevron = Path()
            chevron.move(to: CGPoint(x: -2, y: -3.5))
            chevron.addLine(to: CGPoint(x: 2, y: 0))
            chevron.addLine(to: CGPoint(x: -2, y: 3.5))
            context.stroke(
                chevron.applying(CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)),
                with: .color(.green),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }

    private func diodeRadius() -> CGFloat {
        let screen = geometry.screen
        let horizontal = screen.width / CGFloat(max(layout.top, layout.bottom, 1))
        let vertical = screen.height / CGFloat(max(layout.left, layout.right, 1))
        return min(max(min(horizontal, vertical) * 0.22, 1.8), 3.5)
    }
}

private struct MonitorArtwork: View, Equatable {
    let screen: CGRect

    private static let bezel = Color(red: 0.13, green: 0.14, blue: 0.17)
    private static let panelTop = Color(red: 0.035, green: 0.043, blue: 0.058)
    private static let panelBottom = Color(red: 0.02, green: 0.024, blue: 0.035)
    private static let bezelWidth: CGFloat = 7

    var body: some View {
        Canvas { context, _ in
            let body = screen.insetBy(dx: -Self.bezelWidth, dy: -Self.bezelWidth)
            let bodyPath = RoundedRectangle(cornerRadius: 12).path(in: body)

            context.drawLayer { shadow in
                shadow.addFilter(.blur(radius: 28))
                shadow.fill(
                    RoundedRectangle(cornerRadius: 16).path(in: body.offsetBy(dx: 0, dy: 18)),
                    with: .color(.black.opacity(0.6)))
            }

            context.fill(bodyPath, with: .color(Self.bezel))
            context.stroke(
                bodyPath,
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.16), .white.opacity(0.02)]),
                    startPoint: CGPoint(x: body.midX, y: body.minY),
                    endPoint: CGPoint(x: body.midX, y: body.maxY)), lineWidth: 1)

            context.fill(
                RoundedRectangle(cornerRadius: 6).path(in: screen),
                with: .linearGradient(
                    Gradient(colors: [Self.panelTop, Self.panelBottom]),
                    startPoint: CGPoint(x: screen.midX, y: screen.minY),
                    endPoint: CGPoint(x: screen.midX, y: screen.maxY)))
        }
    }
}

struct LiveLayoutPreview: View {
    let layout: LEDLayout
    let live: LivePreview
    let geometry: PreviewGeometry
    let showsScreen: Bool

    var body: some View {
        LayoutPreview(
            layout: layout, colors: live.colors, geometry: geometry,
            screenImage: showsScreen ? live.screenImage : nil)
    }
}
