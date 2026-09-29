import Testing

@testable import AurolightCore

struct DawnEffectTests {
    let layout = LEDLayout(top: 4, right: 2, bottom: 4, left: 2)

    @Test func sunriseRampsFromDarkToWarmWhite() {
        let e = EffectSettings(mode: .sunrise, fadeMinutes: 10)
        #expect(EffectRenderer.colors(for: e, layout: layout, time: 0)![0] == .black)
        let end = EffectRenderer.colors(for: e, layout: layout, time: 600)![0]
        #expect(end == RGB(r: 1, g: 0.8, b: 0.55))
        let mid = EffectRenderer.colors(for: e, layout: layout, time: 300)![0]
        #expect(mid.r > mid.g && mid.g > mid.b)
    }

    @Test func sunsetEndsDark() {
        let e = EffectSettings(mode: .sunset, fadeMinutes: 1)
        #expect(EffectRenderer.colors(for: e, layout: layout, time: 120)![0] == .black)
    }
}
