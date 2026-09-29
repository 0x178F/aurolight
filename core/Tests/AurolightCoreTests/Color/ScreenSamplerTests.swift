import Foundation
import Testing

@testable import AurolightCore

struct ScreenSamplerTests {
    let width = 480, height = 200
    let layout = LEDLayout(top: 48, right: 20, bottom: 48, left: 20)

    func frame(_ paint: (Double, Double) -> (Double, Double, Double)) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = paint((Double(x) + 0.5) / Double(width), (Double(y) + 0.5) / Double(height))
                let o = (y * width + x) * 4
                pixels[o] = UInt8(b * 255); pixels[o + 1] = UInt8(g * 255); pixels[o + 2] = UInt8(r * 255)
            }
        }
        return pixels
    }

    func stripes(red: Int, blue: Int) -> [UInt8] {
        frame { _, y in Int(y * Double(height)) % (red + blue) < red ? (0.8, 0.05, 0.05) : (0.05, 0.1, 0.8) }
    }

    func step(_ sampler: inout ScreenSampler, _ pixels: [UInt8]) -> [RGB] {
        pixels.withUnsafeBytes {
            sampler.sample(
                bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4, layout: layout,
                immersion: 0.5)
        }
    }

    func blob(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ r: Double) -> Bool {
        hypot(x - cx, (y - cy) * Double(height) / Double(width)) < r
    }

    func sample(_ pixels: [UInt8], immersion: Double, frames: Int = 4) -> [RGB] {
        var sampler = ScreenSampler()
        var colors: [RGB] = []
        for _ in 0..<frames {
            colors = pixels.withUnsafeBytes {
                sampler.sample(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4,
                    layout: layout, immersion: immersion)
            }
        }
        return colors
    }

    func mean(_ colors: [RGB], _ edge: ScreenEdge, _ filter: (Double) -> Bool = { _ in true }) -> RGB {
        let slots = layout.slots()
        let picked = slots.indices.filter { slots[$0].edge == edge && filter(slots[$0].position) }.map { colors[$0] }
        let n = Double(max(picked.count, 1))
        return RGB(
            r: picked.map(\.r).reduce(0, +) / n, g: picked.map(\.g).reduce(0, +) / n,
            b: picked.map(\.b).reduce(0, +) / n)
    }

    @Test func colorfulEdgesKeepTheirColorWhateverIsInTheMiddle() {
        let pixels = frame { x, _ in x < 0.15 ? (0.9, 0.1, 0.1) : x > 0.85 ? (0.1, 0.2, 0.9) : (0.95, 0.95, 0.95) }
        let colors = sample(pixels, immersion: 0.8)
        let left = mean(colors, .left), right = mean(colors, .right)
        #expect(left.r > 0.8 && left.g < 0.2 && left.b < 0.2)
        #expect(right.b > 0.8 && right.r < 0.2)
    }

    @Test func neutralEdgeBorrowsTheNearestColor() {
        let pixels = frame { x, y in
            (x > 0.12 && x < 0.3 && y > 0.2 && y < 0.8) ? (0.85, 0.15, 0.15) : (0.95, 0.95, 0.95)
        }
        let colors = sample(pixels, immersion: 0.5)
        let left = mean(colors, .left) { $0 > 0.35 && $0 < 0.65 }
        let right = mean(colors, .right)
        #expect(left.r > left.g * 2.5)
        #expect(abs(right.r - right.g) < 0.02)
    }

    @Test func edgeOnlyWithoutImmersion() {
        let pixels = frame { x, y in
            (x > 0.12 && x < 0.3 && y > 0.2 && y < 0.8) ? (0.85, 0.15, 0.15) : (0.95, 0.95, 0.95)
        }
        let left = mean(sample(pixels, immersion: 0), .left)
        #expect(abs(left.r - left.g) < 0.02)
    }

    @Test func smallIconsDoNotTintTheEdge() {
        let pixels = frame { x, y in blob(x, y, 0.06, 0.5, 0.012) ? (0.9, 0.1, 0.1) : (0.95, 0.95, 0.95) }
        let left = mean(sample(pixels, immersion: 0.5), .left) { $0 > 0.4 && $0 < 0.6 }
        #expect(left.r - left.g < 0.06)
    }

    @Test func neutralContentStaysNeutral() {
        let pixels = frame { _, _ in (0.8, 0.8, 0.8) }
        for color in sample(pixels, immersion: 1) {
            #expect(max(color.r, color.g, color.b) - min(color.r, color.g, color.b) < 0.02)
        }
    }

    @Test func dominantHueWinsOverAMix() {
        let pixels = frame { x, y in
            blob(x, y, 0.2, 0.4, 0.08)
                ? (0.9, 0.1, 0.1) : blob(x, y, 0.22, 0.62, 0.045) ? (0.1, 0.2, 0.9) : (0.02, 0.02, 0.02)
        }
        let left = mean(sample(pixels, immersion: 0.6), .left) { $0 > 0.45 && $0 < 0.55 }
        #expect(left.r > left.b * 3)
    }

    @Test func blueCountsAsMuchAsGreen() {
        let pixels = frame { x, y in
            blob(x, y, 0.2, 0.3, 0.07)
                ? (0.1, 0.2, 0.95) : blob(x, y, 0.2, 0.75, 0.07) ? (0.1, 0.9, 0.2) : (0.02, 0.02, 0.02)
        }
        let colors = sample(pixels, immersion: 0.5)
        let upper = mean(colors, .left) { $0 < 0.4 }, lower = mean(colors, .left) { $0 > 0.6 }
        #expect(upper.b > upper.g * 2)
        #expect(lower.g > lower.b * 2)
    }

    @Test func centerExplosionLightsTheSidesInItsColor() {
        let pixels = frame { x, y in blob(x, y, 0.5, 0.5, 0.12) ? (1, 0.55, 0.1) : (0.03, 0.03, 0.04) }
        let left = mean(sample(pixels, immersion: 0.5), .left)
        #expect(left.r > 0.15)
        #expect(left.r > left.b * 2)
    }

    @Test func fireworkLightsOnlyItsSide() {
        let pixels = frame { x, y in blob(x, y, 0.3, 0.4, 0.03) ? (0.9, 0.2, 0.9) : (0.02, 0.02, 0.05) }
        let colors = sample(pixels, immersion: 0.5)
        #expect(max(mean(colors, .left).r, mean(colors, .left).b) > 0.06)
        #expect(max(mean(colors, .right).r, mean(colors, .right).b) < 0.06)
    }

    @Test func subtitlesDoNotWashOutTheEdge() {
        let scene = (0.1, 0.15, 0.45)
        let plain = frame { _, _ in scene }
        let subtitled = frame { x, y in
            let stroke = x > 0.3 && x < 0.7 && y > 0.86 && y < 0.93 && Int(x * 160).isMultiple(of: 3)
            return stroke ? (0.97, 0.97, 0.97) : scene
        }
        let center: (Double) -> Bool = { $0 > 0.35 && $0 < 0.65 }
        let before = mean(sample(plain, immersion: 0.4), .bottom, center)
        let after = mean(sample(subtitled, immersion: 0.4), .bottom, center)
        #expect(after.b > after.r * 2)
        #expect(after.r - before.r < 0.1)
    }

    @Test func darkColoredEdgeKeepsItsHueWhenLifted() {
        let pixels = frame { x, y in
            if y < 0.4 { return (0.07, 0.02, 0.12) }
            let window = Int(y * 40).isMultiple(of: 3) && !Int(x * 60).isMultiple(of: 4)
            if window { return Int(x * 10).isMultiple(of: 2) ? (0.1, 0.8, 0.9) : (0.95, 0.6, 0.1) }
            return (0.02, 0.02, 0.03)
        }
        let top = sample(pixels, immersion: 0.4)
        let slots = layout.slots()
        for i in slots.indices where slots[i].edge == .top {
            #expect(top[i].g < 0.4 * top[i].b && top[i].g < 0.5 * top[i].r, "LED \(i): \(top[i])")
        }
    }

    @Test func lightAtAnEdgeDoesNotLiftTheFarSides() {
        let pixels = frame { x, y in blob(x, y, 0.5, 0.06, 0.03) ? (1, 1, 1) : (0.1, 0.1, 0.1) }
        let colors = sample(pixels, immersion: 0.4)
        let slots = layout.slots()
        #expect(mean(colors, .top) { abs($0 - 0.5) < 0.05 }.r > 0.3)
        for i in slots.indices where slots[i].edge == .left || slots[i].edge == .right {
            #expect(max(colors[i].r, colors[i].g, colors[i].b) < 0.12, "\(slots[i].edge) \(slots[i].position)")
        }
    }

    @Test func darkScenesStayDark() {
        let pixels = frame { _, _ in (0.02, 0.02, 0.05) }
        for color in sample(pixels, immersion: 1) {
            #expect(max(color.r, color.g, color.b) < 0.06)
        }
    }

    @Test func equalColorsDoNotFlicker() {
        var sampler = ScreenSampler()
        var hues: [[Bool]] = []
        for f in 0..<40 {
            let k = f.isMultiple(of: 2) ? 0.071 : 0.069
            let pixels = frame { x, y in
                blob(x, y, 0.2, 0.3, k)
                    ? (0.9, 0.1, 0.1) : blob(x, y, 0.2, 0.7, 0.14 - k) ? (0.1, 0.2, 0.9) : (0.02, 0.02, 0.02)
            }
            let colors = pixels.withUnsafeBytes {
                sampler.sample(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4,
                    layout: layout, immersion: 0.6)
            }
            let slots = layout.slots()
            let middle = slots.indices.filter { slots[$0].edge == .left && abs(slots[$0].position - 0.5) < 0.05 }
            hues.append(middle.map { colors[$0].r > colors[$0].b })
        }
        let flips = zip(hues.dropFirst(5), hues.dropFirst(6)).filter { $0 != $1 }.count
        #expect(flips == 0)
    }

    @Test func hueChangeNeverGoesBlack() {
        var sampler = ScreenSampler()
        for _ in 0..<5 { _ = step(&sampler, frame { _, _ in (0.6, 0, 0) }) }
        let next = step(&sampler, frame { _, _ in (0, 0, 0.6) })
        #expect(next.allSatisfy { $0.b > 0.5 && $0.r < 0.05 })
    }

    @Test(arguments: [false, true])
    func resetDropsHueHistory(reset: Bool) {
        var sampler = ScreenSampler()
        for _ in 0..<5 { _ = step(&sampler, stripes(red: 12, blue: 8)) }
        if reset { sampler.reset() }
        let next = step(&sampler, stripes(red: 8, blue: 12))
        let slots = layout.slots()
        let bottom = slots.indices.filter { slots[$0].edge == .bottom }
        #expect(bottom.allSatisfy { next[$0].b > next[$0].r } == reset)
    }

    @Test func aStillFrameSettlesWhenHandedOverAgain() {
        var sampler = ScreenSampler()
        for _ in 0..<5 { _ = step(&sampler, stripes(red: 12, blue: 8)) }
        let still = stripes(red: 9, blue: 11)
        let once = step(&sampler, still)
        var settled = once
        for _ in 0..<24 { settled = step(&sampler, still) }  // capture redelivers the still frame after a change
        let bottom = layout.slots().indices.filter { layout.slots()[$0].edge == .bottom }
        #expect(!bottom.allSatisfy { once[$0].b > once[$0].r })
        #expect(bottom.allSatisfy { settled[$0].b > settled[$0].r })
    }

    @Test func tinyFramesGiveOneFiniteColorPerLED() {
        for size in [1, 3] {
            var sampler = ScreenSampler()
            let pixels = [UInt8](repeating: 200, count: size * size * 4)
            let colors = pixels.withUnsafeBytes {
                sampler.sample(
                    bgra: $0.baseAddress!, width: size, height: size, bytesPerRow: size * 4,
                    layout: layout, immersion: 0.5)
            }
            #expect(colors.count == layout.placedCount)
            #expect(colors.allSatisfy { $0.r.isFinite && $0.g.isFinite && $0.b.isFinite })
        }
    }

    @Test func denseCroppedLayoutLightsEveryLED() {
        var dense = LEDLayout(top: 300, right: 20, bottom: 300, left: 20)
        dense.insets = EdgeValues(top: 0, right: 0.45, bottom: 0, left: 0.45)
        var sampler = ScreenSampler()
        let colors = frame { _, _ in (0.1, 0.8, 0.2) }.withUnsafeBytes {
            sampler.sample(
                bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4,
                layout: dense, immersion: 0)
        }
        #expect(colors.count == dense.placedCount)
        #expect(colors.allSatisfy { $0.g > 0.5 })
    }

    @Test func pureBlueLightsAsMuchAsPureGreen() {
        func brightestLeft(_ c: (Double, Double, Double)) -> Double {
            let colors = sample(frame { x, y in blob(x, y, 0.3, 0.5, 0.1) ? c : (0, 0, 0) }, immersion: 0.5)
            let slots = layout.slots()
            return slots.indices.filter { slots[$0].edge == .left }.map {
                max(colors[$0].r, colors[$0].g, colors[$0].b)
            }.max()!
        }
        let blue = brightestLeft((0, 0, 1)), green = brightestLeft((0, 1, 0))
        #expect(blue > 0.3)
        #expect(abs(blue - green) < 0.1)
    }

    @Test func eachLEDKeepsItsOwnEdgeColor() {
        let two = LEDLayout(top: 2, right: 0, bottom: 0, left: 0)
        var sampler = ScreenSampler()
        var colors: [RGB] = []
        for _ in 0..<4 {
            colors = frame { x, _ in x < 0.5 ? (0.1, 0.8, 0.2) : (0.1, 0.2, 0.9) }.withUnsafeBytes {
                sampler.sample(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4,
                    layout: two, immersion: 0)
            }
        }
        #expect(colors[0].g > colors[0].b && colors[1].b > colors[1].g)
    }

    @Test func respectsBlackBars() {
        var bars = layout
        bars.insets = EdgeValues(top: 0.2, right: 0, bottom: 0.2, left: 0)
        let pixels = frame { _, y in (y < 0.2 || y > 0.8) ? (0, 0, 0) : (0.1, 0.8, 0.2) }
        var sampler = ScreenSampler()
        let colors = pixels.withUnsafeBytes {
            sampler.sample(
                bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4,
                layout: bars, immersion: 0)
        }
        let slots = bars.slots()
        let top = slots.indices.filter { slots[$0].edge == .top }.map { colors[$0] }
        #expect(top.allSatisfy { $0.g > 0.5 })
    }
}
