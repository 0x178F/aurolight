import AurolightCore
import Foundation
import Testing

@testable import Aurolight

struct ColorBarTests {
    let size = CGSize(width: 300, height: 40)

    @Test func topIsWhiteAndBottomIsVivid() {
        #expect(ColorBar.color(at: CGPoint(x: 150, y: 0), in: size).saturation == 0)
        #expect(ColorBar.color(at: CGPoint(x: 0, y: 40), in: size) == RGB(r: 1, g: 0, b: 0))
        #expect(ColorBar.color(at: CGPoint(x: 300, y: 40), in: size) == RGB(r: 1, g: 0, b: 0))
    }

    @Test func theKnobSitsWhereTheColorWasPicked() {
        for point in [CGPoint(x: 42, y: 7), CGPoint(x: 150, y: 20), CGPoint(x: 280, y: 39)] {
            let color = ColorBar.color(at: point, in: size)
            let knob = ColorBar.position(hue: color.hue, saturation: color.saturation, in: size)
            #expect(abs(knob.x - point.x) < 1e-6 && abs(knob.y - point.y) < 1e-6)
        }
    }
}
