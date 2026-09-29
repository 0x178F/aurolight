import AurolightCore
import SwiftUI

struct PreviewGeometry {
    static let coordinateSpace = "editor"

    static let ledGap: CGFloat = 16

    let screen: CGRect

    init(size: CGSize, aspectRatio: Double, insets: CGSize) {
        let available = CGSize(
            width: max(size.width - insets.width * 2, 1),
            height: max(size.height - insets.height * 2, 1))
        var width = available.width
        var height = width / aspectRatio
        if height > available.height {
            height = available.height
            width = height * aspectRatio
        }
        screen = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    func ledPoint(for slot: LEDSlot, gap: CGFloat = PreviewGeometry.ledGap) -> CGPoint {
        screen.point(on: slot.edge, at: slot.position, outset: gap)
    }

    func region(_ r: NormRect) -> CGRect {
        CGRect(
            x: screen.minX + r.x * screen.width, y: screen.minY + r.y * screen.height,
            width: r.width * screen.width, height: r.height * screen.height)
    }
}

extension CGRect {
    func point(on edge: ScreenEdge, at position: Double, outset: CGFloat) -> CGPoint {
        let p = CGFloat(position)
        switch edge {
        case .top: return CGPoint(x: minX + p * width, y: minY - outset)
        case .right: return CGPoint(x: maxX + outset, y: minY + p * height)
        case .bottom: return CGPoint(x: minX + p * width, y: maxY + outset)
        case .left: return CGPoint(x: minX - outset, y: minY + p * height)
        }
    }
}

struct ScreenRectKey: PreferenceKey {
    static let coordinateSpace = "window"
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
