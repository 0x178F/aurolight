import Testing

@testable import AurolightCore

struct FireEffectTests {
    @Test func fireIsHotterAtTheBottom() {
        let l = LEDLayout(top: 10, right: 0, bottom: 10, left: 0)
        let slots = l.slots()
        let colors = EffectRenderer.colors(for: EffectSettings(mode: .fire), layout: l, time: 5)!
        var bottom = 0.0, top = 0.0
        for (slot, c) in zip(slots, colors) {
            let heat: Double = c.r + c.g
            if slot.edge == .bottom { bottom += heat } else { top += heat }
        }
        #expect(bottom > top)
    }
}
