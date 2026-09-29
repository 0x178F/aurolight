import Foundation
import Testing

@testable import AurolightCore

struct ColorProcessorTests {
    let neutral = ColorSettings(brightness: 1, smoothing: 0.5, saturation: 1, gamma: 1, blackLevel: 0)

    @Test func passthroughWithNeutralSettings() {
        var p = ColorProcessor(settings: neutral)
        #expect(p.process([RGB(r: 1, g: 0, b: 0.5)]) == [255, 0, 128])
    }

    @Test func smoothingMovesHalfway() {
        var p = ColorProcessor(settings: neutral)
        _ = p.process([.black])
        #expect(p.process([RGB(r: 1, g: 1, b: 1)]) == [128, 128, 128])
    }

    @Test func blackLevelTurnsDimColorsOff() {
        var settings = neutral
        settings.blackLevel = 0.1
        var p = ColorProcessor(settings: settings)
        #expect(p.process([RGB(r: 0.05, g: 0.05, b: 0.05)]) == [0, 0, 0])
    }

    @Test func brightnessScales() {
        var settings = neutral
        settings.brightness = 0.5
        var p = ColorProcessor(settings: settings)
        #expect(p.process([RGB(r: 1, g: 1, b: 1)]) == [128, 128, 128])
    }

    @Test func gammaDarkensMidtones() {
        var settings = neutral
        settings.gamma = 2
        var p = ColorProcessor(settings: settings)
        #expect(p.process([RGB(r: 0.5, g: 0.5, b: 0.5)]) == [64, 64, 64])
    }

    @Test func zeroSaturationGivesAGrayOfTheSameLightness() {
        var settings = neutral
        settings.saturation = 0
        var p = ColorProcessor(settings: settings)
        let (lightness, _, _) = Oklab.fromLinear(r: 1, g: 0, b: 0)
        let gray = ColorProcessor.byte(SRGB.encode(pow(lightness, 3)))
        #expect(p.process([RGB(r: 1, g: 0, b: 0)]) == [gray, gray, gray])
    }

    @Test func highSaturationClamps() {
        var settings = neutral
        settings.saturation = 2
        var p = ColorProcessor(settings: settings)
        let out = p.process([RGB(r: 1, g: 0.5, b: 0.5)])
        #expect(out[0] == 255)
        #expect(out[1] < 128 && out[1] == out[2])
    }

    @Test func unsmoothedReturnsTheTarget() {
        var p = ColorProcessor(settings: neutral)
        _ = p.process([.black])
        #expect(p.process([RGB(r: 1, g: 1, b: 1)], smooth: false) == [255, 255, 255])
    }

    @Test func ledCountChangeDoesNotBlend() {
        var p = ColorProcessor(settings: neutral)
        _ = p.process([.black])
        #expect(p.process([RGB(r: 1, g: 1, b: 1), RGB(r: 1, g: 1, b: 1)]) == [UInt8](repeating: 255, count: 6))
    }

    @Test func fullSmoothingStillMoves() {
        var settings = neutral
        settings.smoothing = 1
        var p = ColorProcessor(settings: settings)
        _ = p.process([.black])
        #expect(p.process([RGB(r: 1, g: 1, b: 1)])[0] > 0)
    }

    @Test func zeroGammaKeepsBlackBlack() {
        var settings = neutral
        settings.gamma = 0
        var p = ColorProcessor(settings: settings)
        #expect(p.process([.black]) == [0, 0, 0])
    }

    @Test func byteHandlesNonFiniteValues() {
        #expect(ColorProcessor.byte(.nan) == 0)
        #expect(ColorProcessor.byte(-.infinity) == 0)
        #expect(ColorProcessor.byte(.infinity) == 255)
    }
}

struct ColorSpaceTests {
    func close(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ tolerance: Double = 1e-3) -> Bool {
        abs(a.0 - b.0) < tolerance && abs(a.1 - b.1) < tolerance && abs(a.2 - b.2) < tolerance
    }

    @Test func oklabMatchesReferenceValues() {
        #expect(close(Oklab.fromLinear(r: 1, g: 1, b: 1), (1, 0, 0)))
        #expect(close(Oklab.fromLinear(r: 1, g: 0, b: 0), (0.6280, 0.2249, 0.1258)))
        #expect(close(Oklab.fromLinear(r: 0, g: 0, b: 1), (0.4520, -0.0325, -0.3115)))
    }

    @Test func oklabRoundTrips() {
        let colors: [(Double, Double, Double)] = [
            (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (0, 1, 1), (1, 0, 1), (0.2, 0.5, 0.8),
        ]
        for c in colors {
            let (l, a, b) = Oklab.fromLinear(r: c.0, g: c.1, b: c.2)
            #expect(close(Oklab.toLinear(lightness: l, a: a, b: b), c, 1e-6))
        }
    }

    @Test func srgbRoundTrips() {
        #expect(abs(SRGB.decode(0.5) - 0.2140) < 1e-4)
        for v in [0, 0.02, 0.04045, 0.05, 0.5, 1] {
            #expect(abs(SRGB.encode(SRGB.decode(v)) - v) < 1e-6)  // the standard's two segments meet only to ~1e-8
        }
    }
}

struct ColorSettingsTests {
    func decode(_ json: String) throws -> ColorSettings {
        try JSONDecoder().decode(ColorSettings.self, from: Data(json.utf8))
    }

    @Test func badFieldKeepsTheOthers() throws {
        let s = try decode(#"{"brightness": 0.3, "gamma": "steep"}"#)
        #expect(s.brightness == 0.3)
        #expect(s.gamma == ColorSettings().gamma)
    }
}

struct ColorPresetTests {
    @Test func selectingAPresetSetsItsTuningAndKeepsBrightness() {
        for preset in ColorPreset.allCases where preset != .custom {
            var color = ColorSettings(brightness: 0.37)
            color.select(.custom)
            color.select(preset)
            #expect(color.preset == preset)
            #expect(ColorPreset.Tuning(color) == preset.values?.tuning)
            #expect(color.brightness == 0.37)
        }
    }

    @Test func immersionIsFreeWithinAPreset() {
        var color = ColorSettings()
        color.select(.cinema)
        color.immersion = 0.1
        #expect(color.preset == .cinema)
    }

    @Test func customStartsFromTheCurrentTuningAndIsRemembered() {
        var color = ColorSettings()
        color.select(.vivid)
        color.select(.custom)
        #expect(ColorPreset.Tuning(color) == ColorPreset.vivid.values?.tuning)

        color.gamma = 2.6
        color.select(.natural)
        #expect(color.gamma == 2.2)
        color.select(.custom)
        #expect(color.gamma == 2.6)
    }

    @Test func defaultsAreNatural() {
        #expect(ColorSettings().preset == .natural)
        #expect(ColorPreset.Tuning(ColorSettings()) == ColorPreset.natural.values?.tuning)
    }

    @Test(arguments: [("2.2", ColorPreset.natural), ("2.5", ColorPreset.custom)])
    func settingsSavedWithoutAPresetGetTheOneTheyMatch(gamma: String, expected: ColorPreset) throws {
        let json = #"{"brightness":0.5,"smoothing":0.6,"saturation":1,"gamma":\#(gamma),"blackLevel":0.03}"#
        let color = try JSONDecoder().decode(ColorSettings.self, from: Data(json.utf8))
        #expect(color.preset == expected)
        #expect(color.brightness == 0.5)
    }

    @Test func aSavedPresetGetsItsCurrentTuning() throws {
        let json =
            #"{"brightness":0.5,"smoothing":0.6,"saturation":1,"gamma":1.4,"blackLevel":0.03,"preset":"natural"}"#
        let color = try JSONDecoder().decode(ColorSettings.self, from: Data(json.utf8))
        #expect(color.preset == .natural && color.gamma == 2.2 && color.brightness == 0.5)
    }

    @Test func naturalLightsTheStripWithTheScreensLight() {
        var natural = ColorSettings()
        natural.brightness = 1
        for v in [0.2, 0.5, 0.8] {
            let led = ColorProcessor.finalize(RGB(r: v, g: v, b: v), natural)
            #expect(abs(led.r - SRGB.decode(v)) < 0.01, "encoded \(v)")
        }
        let orange = RGB(r: 1, g: 0.5, b: 0.1)
        let led = ColorProcessor.finalize(orange, natural)
        #expect(abs(led.g / led.r - SRGB.decode(0.5)) < 0.01)
    }

    @Test func saturationKeepsHueAndStaysInGamut() {
        let colors = [RGB(r: 0.9, g: 0.5, b: 0.3), RGB(r: 0.2, g: 0.6, b: 0.9), RGB(r: 1, g: 0.2, b: 0.1)]
        for c in colors {
            let boosted = Oklab.saturate(c, by: 1.6)
            #expect([boosted.r, boosted.g, boosted.b].allSatisfy { (0...1).contains($0) })
            let hue = { (c: RGB) -> Double in
                let (_, a, b) = Oklab.fromLinear(r: SRGB.decode(c.r), g: SRGB.decode(c.g), b: SRGB.decode(c.b))
                return atan2(b, a)
            }
            #expect(abs(hue(boosted) - hue(c)) < 0.02)
            #expect(boosted.saturation >= c.saturation)
        }
        let same = Oklab.saturate(RGB(r: 0.4, g: 0.5, b: 0.6), by: 1)
        #expect(abs(same.r - 0.4) < 1e-4 && abs(same.b - 0.6) < 1e-4)
    }

    @Test func presetAndCustomTuningAreSaved() throws {
        var color = ColorSettings()
        color.select(.custom)
        color.gamma = 2
        color.select(.cinema)
        let decoded = try JSONDecoder().decode(ColorSettings.self, from: JSONEncoder().encode(color))
        #expect(decoded == color)
    }

    @Test func hsvPrimaries() {
        #expect(RGB(hue: 0, saturation: 1, value: 1) == RGB(r: 1, g: 0, b: 0))
        #expect(RGB(hue: 1.0 / 3, saturation: 1, value: 1) == RGB(r: 0, g: 1, b: 0))
        #expect(RGB(hue: 1, saturation: 1, value: 1) == RGB(r: 1, g: 0, b: 0))
        #expect(RGB(hue: -2.0 / 3, saturation: 1, value: 1) == RGB(r: 0, g: 1, b: 0))
        #expect(RGB(hue: .nan, saturation: 1, value: 1) == RGB(r: 1, g: 0, b: 0))
        #expect(RGB(hue: .infinity, saturation: 1, value: 1) == RGB(r: 1, g: 0, b: 0))
    }

    @Test func hueAndSaturationRoundTrip() {
        for hue in stride(from: 0.0, to: 1, by: 0.05) {
            for saturation in [0.2, 0.6, 1] {
                let rgb = RGB(hue: hue, saturation: saturation, value: 1)
                #expect(abs(rgb.hue - hue) < 1e-9)
                #expect(abs(rgb.saturation - saturation) < 1e-9)
            }
        }
        #expect(RGB(r: 1, g: 1, b: 1).saturation == 0 && RGB(r: 1, g: 1, b: 1).hue == 0)
        #expect(RGB.black.saturation == 0)
    }
}
