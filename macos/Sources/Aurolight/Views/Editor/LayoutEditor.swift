import AurolightCore
import SwiftUI

struct LayoutEditor: View {
    @Binding var layout: LEDLayout
    let live: LivePreview
    let aspectRatio: Double
    var showsScreen = true
    var skippedArea = EdgeValues.uniform(0)

    @State private var hoveredLED: Int?
    @State private var isDraggingStart = false
    @State private var isHoveringScreen = false
    @Namespace private var glass

    private let insets = CGSize(width: 110, height: 78)

    private var sampledLayout: LEDLayout {
        var sampled = layout
        sampled.insets = skippedArea
        return sampled
    }

    var body: some View {
        GeometryReader { proxy in
            let geo = PreviewGeometry(size: proxy.size, aspectRatio: aspectRatio, insets: insets)
            let screen = geo.screen

            GlassEffectContainer(spacing: 20) {
                ZStack {
                    LiveLayoutPreview(layout: sampledLayout, live: live, geometry: geo, showsScreen: showsScreen)

                    ledTargets(geo)

                    edgeControl("Top", value: $layout.top, axis: .horizontal)
                        .position(x: screen.midX, y: screen.minY - 52)
                    edgeControl("Bottom", value: $layout.bottom, axis: .horizontal)
                        .position(x: screen.midX, y: screen.maxY + 52)
                    edgeControl("Left", value: $layout.left, axis: .vertical)
                        .position(x: screen.minX - 62, y: screen.midY)
                    edgeControl("Right", value: $layout.right, axis: .vertical)
                        .position(x: screen.maxX + 62, y: screen.midY)

                    StartHandle(layout: $layout, isDragging: $isDraggingStart, geometry: geo)

                    ledCountBadge
                        .position(x: screen.midX, y: screen.midY)
                        .allowsHitTesting(false)

                    if isHoveringScreen, let start = layout.slots().first {
                        reverseButton
                            .glassEffectID("reverse", in: glass)
                            .position(outside(start, geo, by: 34))
                    }
                }
            }
            .coordinateSpace(.named(PreviewGeometry.coordinateSpace))
            .onContinuousHover(coordinateSpace: .named(PreviewGeometry.coordinateSpace)) { phase in
                if case let .active(point) = phase {
                    isHoveringScreen = screen.insetBy(dx: -48, dy: -48).contains(point)
                } else {
                    isHoveringScreen = false
                }
            }
            .animation(.easeOut(duration: 0.18), value: isHoveringScreen)
            .preference(
                key: ScreenRectKey.self,
                value: screen.offsetBy(
                    dx: proxy.frame(in: .named(ScreenRectKey.coordinateSpace)).minX,
                    dy: proxy.frame(in: .named(ScreenRectKey.coordinateSpace)).minY))
        }
        .animation(isDraggingStart ? nil : .smooth(duration: 0.25), value: layout)
        .animation(.smooth(duration: 0.4), value: skippedArea)
    }

    private var ledCountBadge: some View {
        Text("\(layout.placedCount) LEDs")
            .font(.callout.weight(.medium).monospacedDigit())
            .contentTransition(.numericText())
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .animation(.smooth(duration: 0.25), value: layout.placedCount)
    }

    private func ledTargets(_ geo: PreviewGeometry) -> some View {
        let slots = layout.slots()
        return ForEach(slots.indices.dropFirst(), id: \.self) { i in
            Circle()
                .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                .opacity(hoveredLED == i ? 1 : 0)
                .frame(width: 18, height: 18)
                .contentShape(.circle)
                .position(geo.ledPoint(for: slots[i]))
                .onHover { hoveredLED = $0 ? i : (hoveredLED == i ? nil : hoveredLED) }
                .onTapGesture { layout.makeStart(stripIndex: i) }
                .help("LED \(i). Click to start the strip here.")
                .accessibilityHidden(true)
        }
    }

    private func edgeControl(_ title: String, value: Binding<Int>, axis: Axis) -> some View {
        CountControl(title: title, value: value, axis: axis)
            .glassEffect(.regular.interactive(), in: .capsule)
            .opacity(value.wrappedValue == 0 ? 0.6 : 1)
    }

    private func outside(_ slot: LEDSlot, _ geo: PreviewGeometry, by distance: CGFloat) -> CGPoint {
        geo.ledPoint(for: slot, gap: PreviewGeometry.ledGap + distance)
    }

    private var reverseButton: some View {
        Button {
            layout.reverseDirection()
        } label: {
            Label("Reverse direction", systemImage: "arrow.left.arrow.right")
                .labelStyle(.iconOnly)
                .font(.caption.weight(.semibold))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help("Reverse the direction. The first LED stays where it is.")
    }
}
