import Foundation
import Testing

@testable import AurolightCore

struct EffectTests {
    let layout = LEDLayout(top: 4, right: 2, bottom: 4, left: 2)

    @Test func screenModeHasNoEffectFrame() {
        #expect(EffectRenderer.colors(for: EffectSettings(mode: .screen), layout: layout, time: 1) == nil)
    }

    @Test(arguments: LightMode.allCases.filter { $0 != .screen })
    func effectsCoverEveryPlacedLED(mode: LightMode) {
        let colors = EffectRenderer.colors(for: EffectSettings(mode: mode), layout: layout, time: 3.3)
        #expect(colors?.count == layout.placedCount)
    }

    @Test(arguments: LightMode.allCases.filter { $0 != .screen })
    func effectsArePureFunctionsOfTime(mode: LightMode) {
        let settings = EffectSettings(mode: mode)
        let first = EffectRenderer.colors(for: settings, layout: layout, time: 7.25)
        _ = EffectRenderer.colors(for: settings, layout: layout, time: 2)
        #expect(EffectRenderer.colors(for: settings, layout: layout, time: 7.25) == first)
    }

    @Test func solidUsesTheChosenColor() {
        let red = RGB(r: 1, g: 0, b: 0)
        let colors = EffectRenderer.colors(for: EffectSettings(mode: .solid, color: red), layout: layout, time: 0)
        #expect(colors?.allSatisfy { $0 == red } == true)
    }

    @Test func breathingStaysBetweenFloorAndFullColor() {
        let white = RGB(r: 1, g: 1, b: 1)
        for t in stride(from: 0.0, to: 20, by: 0.37) {
            let c = EffectRenderer.colors(
                for: EffectSettings(mode: .breathing, color: white), layout: layout, time: t)![0]
            #expect(c.r >= 0.12 - 1e-9 && c.r <= 1 + 1e-9)
        }
    }

    @Test func rainbowSpreadsHuesAlongTheStrip() {
        let colors = EffectRenderer.colors(for: EffectSettings(mode: .rainbow), layout: layout, time: 0)!
        #expect(colors[0] == RGB(r: 1, g: 0, b: 0))
        #expect(Set(colors).count == colors.count)
    }

    @Test(arguments: LightMode.allCases.filter { $0 != .screen })
    func effectsStayInRange(mode: LightMode) {
        for t in stride(from: 0.0, to: 30, by: 0.73) {
            for c in EffectRenderer.colors(for: EffectSettings(mode: mode, speed: 0.7), layout: layout, time: t)! {
                #expect([c.r, c.g, c.b].allSatisfy { $0 >= -1e-9 && $0 <= 1 + 1e-9 })
            }
        }
    }

    @Test(arguments: LightMode.allCases.filter { $0 != .screen && $0 != .music })
    func controlsMatchRenderer(mode: LightMode) {
        func frame(color: RGB = RGB(r: 1, g: 0.55, b: 0.2), speed: Double = 0.4, time: Double = 3.3) -> [RGB]? {
            EffectRenderer.colors(
                for: EffectSettings(mode: mode, color: color, speed: speed), layout: layout, time: time)
        }
        let red = RGB(r: 1, g: 0, b: 0), blue = RGB(r: 0, g: 0, b: 1)
        #expect((frame(color: red) != frame(color: blue)) == mode.controls.contains(.color))
        #expect((frame(speed: 0.2) != frame(speed: 0.8)) == mode.controls.contains(.speed))
        if mode.controls.contains(.speed) {
            let frames = [0.37, 1.1, 2.9].map { frame(time: $0) }
            #expect(Set(frames.compactMap { $0 }).count > 1)
        }
    }

    @Test func unknownModeFallsBackAlone() throws {
        let json = #"{"mode":"removedMode","speed":2}"#
        let decoded = try JSONDecoder().decode(EffectSettings.self, from: Data(json.utf8))
        #expect(decoded.mode == EffectSettings().mode)
        #expect(decoded.speed == 2)
    }
}
