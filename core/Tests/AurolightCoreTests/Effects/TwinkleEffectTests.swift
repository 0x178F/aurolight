import Testing

@testable import AurolightCore

struct TwinkleEffectTests {
    let layout = LEDLayout(top: 48, right: 27, bottom: 48, left: 27)
    let settings = EffectSettings(mode: .twinkle, color: RGB(r: 1, g: 1, b: 1), speed: 0.5)

    @Test func aFewLEDsFlashAtATimeOverADimBase() {
        var flashing = 0, samples = 0
        var everFlashed = Set<Int>()
        for step in 0..<200 {
            let colors = EffectRenderer.colors(for: settings, layout: layout, time: Double(step) * 0.25)!
            for (i, c) in colors.enumerated() {
                #expect(c.r >= 0.25 - 1e-9)
                if c.r > 0.5 {
                    flashing += 1
                    everFlashed.insert(i)
                }
                samples += 1
            }
        }
        let share = Double(flashing) / Double(samples)
        #expect(share > 0.02 && share < 0.12)
        #expect(everFlashed.count > layout.placedCount / 2)
    }
}
