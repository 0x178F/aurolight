import AurolightCore
import SwiftUI

struct StartHandle: View {
    @Binding var layout: LEDLayout
    @Binding var isDragging: Bool
    let geometry: PreviewGeometry

    var body: some View {
        if let first = layout.slots().first {
            Circle()
                .fill(.clear)
                .frame(width: 26, height: 26)
                .contentShape(.circle)
                .position(geometry.ledPoint(for: first))
                .pointerStyle(isDragging ? .grabActive : .grabIdle)
                .gesture(drag)
                .help("Start (LED 0). Drag along the strip to where your cable is connected.")
                .accessibilityElement()
                .accessibilityLabel("Strip start")
                .accessibilityValue("First LED on the \(first.edge.rawValue) edge")
                .accessibilityAction(named: "Reverse direction") { layout.reverseDirection() }
                .accessibilityAdjustableAction { direction in
                    let count = layout.slots().count
                    guard count > 1 else { return }
                    switch direction {
                    case .increment: layout.makeStart(stripIndex: 1)
                    case .decrement: layout.makeStart(stripIndex: count - 1)
                    @unknown default: break
                    }
                }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(PreviewGeometry.coordinateSpace))
            .onChanged { value in
                isDragging = true
                let slots = layout.slots()
                guard
                    let nearest = slots.indices.min(by: {
                        distance(geometry.ledPoint(for: slots[$0]), value.location)
                            < distance(geometry.ledPoint(for: slots[$1]), value.location)
                    }), nearest != 0
                else { return }
                layout.makeStart(stripIndex: nearest)
            }
            .onEnded { _ in isDragging = false }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
