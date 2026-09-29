import Foundation
import Testing

@testable import AurolightCore

struct WhiteBalanceTests {
    @Test func neutralChangesNothing() {
        #expect(WhiteBalance.neutral.gains == RGB(r: 1, g: 1, b: 1))
        let colors = [RGB(r: 0.2, g: 0.7, b: 0.4), RGB(r: 1, g: 1, b: 1)]
        var plain = ColorProcessor(), balanced = ColorProcessor()
        balanced.gains = WhiteBalance.neutral.gains
        #expect(plain.process(colors) == balanced.process(colors))
    }

    @Test func warmerCutsBlueCoolerCutsRed() {
        let warm = WhiteBalance(temperature: 4000).gains
        #expect(warm.r == 1 && warm.g < 1 && warm.b < warm.g)
        let cool = WhiteBalance(temperature: 9000).gains
        #expect(cool.b == 1 && cool.r < 1)
    }

    @Test func tintMovesBetweenGreenAndMagenta() {
        let magenta = WhiteBalance(tint: 1).gains, green = WhiteBalance(tint: -1).gains
        #expect(magenta.g < magenta.r && magenta.g < magenta.b)
        #expect(green.g == 1 && green.r < 1 && green.b < 1)
    }

    @Test func outOfRangeValuesAreClamped() {
        #expect(WhiteBalance(temperature: 100).gains == WhiteBalance(temperature: 3000).gains)
        #expect(WhiteBalance(tint: 5).gains == WhiteBalance(tint: 1).gains)
    }

    @Test func missingFieldsDecodeAsNeutral() throws {
        let decoded = try JSONDecoder().decode(WhiteBalance.self, from: Data("{}".utf8))
        #expect(decoded == .neutral)
    }

    @Test func testColorLightsEveryLEDWithTheBalanceApplied() throws {
        var renderer = LightFrameRenderer()
        let layout = LEDLayout(top: 4, right: 2, bottom: 4, left: 2)
        var color = ColorSettings()
        color.brightness = 1
        let input = LightFrameRenderer.Input(
            layout: layout, color: color, effects: EffectSettings(mode: .screen),
            whiteBalance: WhiteBalance(temperature: 4000), testColor: RGB(r: 1, g: 1, b: 1))
        let rendered = renderer.render(input)
        let bytes = try #require(rendered).bytes
        #expect(bytes.count == layout.placedCount * 3)
        #expect(bytes[0] == 255 && bytes[2] < bytes[1])
        let blues = Set(stride(from: 2, to: bytes.count, by: 3).map { bytes[$0] })
        #expect(blues.count == 1)
    }
}
