import Foundation
import Testing

@testable import AurolightCore

struct HorizonEffectTests {
    @Test func warmBelowCoolAbove() {
        let layout = LEDLayout(top: 20, right: 12, bottom: 20, left: 12)
        let slots = layout.slots()
        for time in stride(from: 0.0, to: 60, by: 7.5) {
            let colors = EffectRenderer.colors(for: EffectSettings(mode: .horizon), layout: layout, time: time)!
            for (slot, c) in zip(slots, colors) {
                if slot.edge == .bottom { #expect(c.r > c.b) }
                if slot.edge == .top { #expect(c.b > c.r) }
            }
        }
    }
}
