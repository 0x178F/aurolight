import Testing

@testable import AurolightCore

struct LightFrameRendererTests {
    let layout = LEDLayout(top: 2, right: 0, bottom: 0, left: 0)
    let gray = RGB(r: 0.5, g: 0.5, b: 0.5)

    func input(
        _ mode: LightMode, color: ColorSettings = ColorSettings(), samples: [RGB] = [],
        sceneCut: Bool = false
    ) -> LightFrameRenderer.Input {
        .init(layout: layout, color: color, effects: EffectSettings(mode: mode), samples: samples, sceneCut: sceneCut)
    }

    @Test func screenWaitsForSamplesThatFitTheLayout() {
        var renderer = LightFrameRenderer()
        #expect(renderer.render(input(.screen)) == nil)
        #expect(renderer.render(input(.screen, samples: [gray])) == nil)
        #expect(renderer.render(input(.screen, samples: [gray, gray]))?.bytes.count == 6)
    }

    @Test func effectsKeepTheirColorsWhateverTheScreenSettings() {
        var color = ColorSettings()
        color.saturation = 0
        color.blackLevel = 1
        var renderer = LightFrameRenderer()
        let frame = renderer.render(
            .init(
                layout: layout, color: color,
                effects: EffectSettings(mode: .solid, color: RGB(r: 1, g: 0, b: 0))))
        #expect(frame?.bytes[0] ?? 0 > 200 && frame?.bytes[1] == 0)
    }

    @Test func sceneCutSkipsTheFade() {
        let red = [RGB(r: 1, g: 0, b: 0), RGB(r: 1, g: 0, b: 0)]
        let blue = [RGB(r: 0, g: 0, b: 1), RGB(r: 0, g: 0, b: 1)]
        func afterSwitch(cut: Bool) -> [RGB] {
            var renderer = LightFrameRenderer()
            _ = renderer.render(input(.screen, samples: red))
            return renderer.render(input(.screen, samples: blue, sceneCut: cut))!.preview
        }
        #expect(afterSwitch(cut: true) == blue)
        #expect(afterSwitch(cut: false)[0].r > 0)
    }

    @Test func animatedEffectsAreNotSmoothed() {
        var color = ColorSettings()
        color.smoothing = 0.9
        var renderer = LightFrameRenderer()
        let rainbow = { (t: Double) in
            LightFrameRenderer.Input(layout: layout, color: color, effects: EffectSettings(mode: .rainbow), time: t)
        }
        let target = EffectRenderer.colors(for: EffectSettings(mode: .rainbow), layout: layout, time: 3)!
        _ = renderer.render(rainbow(0))
        #expect(renderer.render(rainbow(3))!.preview == target)
    }
}
