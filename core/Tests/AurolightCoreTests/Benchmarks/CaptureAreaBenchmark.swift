import Foundation
import Testing

@testable import AurolightCore

/// Slow (~1 min), so it only runs on request: `make benchmark` (sets AUROLIGHT_BENCHMARK=1).
struct CaptureAreaBenchmark {
    struct Frame {
        var pixels: [UInt8]
        var truth: EdgeValues
        var time: Double
    }

    struct Scenario {
        let name: String
        let width: Int
        let height: Int
        let frames: [Frame]
        let settle: Double
        var allowsOffCenter = false
    }

    struct Result {
        let name: String
        var settledFrames = 0
        var totalFrames = 0
        var accurate = 0
        var falseCrop = 0
        var worstLatency = 0.0
        var accuracy: Double { settledFrames == 0 ? 1 : Double(accurate) / Double(settledFrames) }
        var falseCropRate: Double { totalFrames == 0 ? 0 : Double(falseCrop) / Double(totalFrames) }
    }

    static func noise(_ x: Int, _ y: Int, _ t: Int) -> Double {
        let v = sin(Double(x) * 12.9898 + Double(y) * 78.233 + Double(t) * 37.719) * 43758.5453
        return v - v.rounded(.down)
    }

    static func picture(_ x: Int, _ y: Int, _ t: Int, level: Double) -> (Double, Double, Double) {
        let u = Double(x) / 37, v = Double(y) / 23, tt = Double(t) / 10
        let r = 0.5 + 0.35 * sin(u + tt) + 0.15 * noise(x, y, t)
        let g = 0.45 + 0.35 * sin(v * 1.3 - tt * 0.7) + 0.15 * noise(y, x, t)
        let b = 0.5 + 0.35 * sin((u + v) * 0.8 + tt * 1.1)
        return (r * level, g * level, b * level)
    }

    static func frame(
        width: Int, height: Int, t: Int, bars: EdgeValues, barBlack: Double = 0, barNoise: Double = 4,
        level: Double = 1, paint: ((Int, Int) -> (Double, Double, Double)?)? = nil
    ) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: width * height * 4)
        let top = Int((bars.top * Double(height)).rounded()), bottom = Int((bars.bottom * Double(height)).rounded())
        let left = Int((bars.left * Double(width)).rounded()), right = Int((bars.right * Double(width)).rounded())
        for y in 0..<height {
            for x in 0..<width {
                var c: (Double, Double, Double)
                let inBar = y < top || y >= height - bottom || x < left || x >= width - right
                if inBar {
                    let n = (noise(x, y, t) - 0.5) * barNoise / 255
                    let k = barBlack / 255 + n
                    c = (k, k, k)
                } else {
                    c = picture(x, y, t, level: level)
                }
                if let p = paint?(x, y) { c = p }
                let o = (y * width + x) * 4
                px[o] = UInt8(max(0, min(1, c.2)) * 255)
                px[o + 1] = UInt8(max(0, min(1, c.1)) * 255)
                px[o + 2] = UInt8(max(0, min(1, c.0)) * 255)
            }
        }
        return px
    }

    static let ultrawide = (w: 480, h: 200)
    static let wide = (w: 480, h: 270)

    static func sequence(
        _ name: String, size: (w: Int, h: Int), seconds: Double, fps: Double = 30, settle: Double = 2.5,
        offCenter: Bool = false, truth: (Double) -> EdgeValues,
        render: (Int, Double, EdgeValues) -> [UInt8]
    ) -> Scenario {
        var frames: [Frame] = []
        var t = 0.0, i = 0
        while t < seconds {
            let bars = truth(t)
            frames.append(Frame(pixels: render(i, t, bars), truth: bars, time: t))
            t += 1 / fps; i += 1
        }
        return Scenario(
            name: name, width: size.w, height: size.h, frames: frames, settle: settle, allowsOffCenter: offCenter)
    }

    static var scenarios: [Scenario] {
        let letterbox239on169 = (1 - (16.0 / 9) / 2.39) / 2
        let pillar169on24 = (1 - (16.0 / 9) / 2.4) / 2
        let none = EdgeValues.uniform(0)
        return [
            sequence("No bars, bright video", size: wide, seconds: 6, truth: { _ in none }) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b)
            },
            sequence("No bars, dark video", size: wide, seconds: 6, truth: { _ in none }) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b, level: 0.25)
            },
            sequence(
                "Letterbox 2.39 on 16:9", size: wide, seconds: 6,
                truth: { _ in EdgeValues(top: letterbox239on169, right: 0, bottom: letterbox239on169, left: 0) }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b)
            },
            sequence(
                "Letterbox, limited-range black (16) + noise", size: wide, seconds: 6,
                truth: { _ in EdgeValues(top: letterbox239on169, right: 0, bottom: letterbox239on169, left: 0) }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b, barBlack: 16, barNoise: 10)
            },
            sequence(
                "Pillarbox 16:9 on 21:9", size: ultrawide, seconds: 6,
                truth: { _ in EdgeValues(top: 0, right: pillar169on24, bottom: 0, left: pillar169on24) }
            ) { i, _, b in
                frame(width: ultrawide.w, height: ultrawide.h, t: i, bars: b)
            },
            sequence(
                "Subtitles in the bottom bar", size: wide, seconds: 6,
                truth: { _ in EdgeValues(top: letterbox239on169, right: 0, bottom: letterbox239on169, left: 0) }
            ) { i, _, b in
                var px = frame(width: wide.w, height: wide.h, t: i, bars: b)
                let y0 = wide.h - Int(letterbox239on169 * Double(wide.h)) / 2 - 4
                for y in y0..<(y0 + 7) {
                    for x in 150..<330 where (x / 6) % 3 != 2 {
                        let o = (y * wide.w + x) * 4
                        px[o] = 235; px[o + 1] = 235; px[o + 2] = 235
                    }
                }
                return px
            },
            sequence("Symmetric night scene (no bars)", size: wide, seconds: 6, truth: { _ in none }) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b) { _, y in
                    let v = Double(y) / Double(wide.h)
                    let edgeDistance = min(v, 1 - v)
                    if edgeDistance < 0.22 {
                        let k = 0.01 + edgeDistance * 0.35
                        return (k, k, k * 1.3)
                    }
                    return nil
                }
            },
            sequence(
                "Fade to black mid-letterbox", size: wide, seconds: 8,
                truth: { _ in EdgeValues(top: letterbox239on169, right: 0, bottom: letterbox239on169, left: 0) }
            ) { i, t, b in
                let level = t < 3 ? 1 : t < 3.5 ? 1 - (t - 3) * 2 : t < 4.5 ? 0 : min(1, (t - 4.5) * 2)
                return frame(width: wide.w, height: wide.h, t: i, bars: b, level: level)
            },
            sequence(
                "Cut from 2.39 to 16:9 (bars go away)", size: wide, seconds: 8,
                truth: { t in
                    t < 4 ? EdgeValues(top: letterbox239on169, right: 0, bottom: letterbox239on169, left: 0) : none
                }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b)
            },
            sequence(
                "Paused: bright progress bar over the bottom bar", size: wide, seconds: 6,
                truth: { _ in EdgeValues(top: letterbox239on169, right: 0, bottom: letterbox239on169, left: 0) }
            ) { i, t, b in
                frame(width: wide.w, height: wide.h, t: t > 3 ? 90 : i, bars: b) { x, y in
                    t > 3 && y >= wide.h - 18 && y < wide.h - 12 && x > 20 && x < wide.w - 20 ? (0.9, 0.2, 0.2) : nil
                }
            },
            sequence(
                "Letterbox, dark night scene at the bottom", size: wide, seconds: 6,
                truth: { _ in EdgeValues(top: letterbox239on169, right: 0, bottom: letterbox239on169, left: 0) }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b) { _, y in
                    y > wide.h / 2 && y < wide.h - Int(letterbox239on169 * Double(wide.h)) ? (0.04, 0.05, 0.1) : nil
                }
            },
            sequence(
                "Notch band in full-screen video", size: (w: 480, h: 310), seconds: 6,
                truth: { _ in EdgeValues(top: 0.033, right: 0, bottom: 0, left: 0) }
            ) { i, _, b in
                frame(width: 480, height: 310, t: i, bars: b)
            },
            sequence(
                "Letterbox, low frame rate", size: wide, seconds: 8, fps: 3,
                truth: { _ in EdgeValues(top: letterbox239on169, right: 0, bottom: letterbox239on169, left: 0) }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b)
            },
        ] + beyondBlackBars
    }

    static var beyondBlackBars: [Scenario] {
        let letterbox = (1 - (16.0 / 9) / 2.39) / 2
        let pillar = (1 - (16.0 / 9) / 2.4) / 2
        let video = EdgeValues(top: 0.2, right: 0.2, bottom: 0.25, left: 0.2)
        func scrollShift(_ t: Double) -> Int { Int(min(max(t - 4, 0) * 2, 1) * 12) }
        func scrolledVideo(_ t: Double) -> EdgeValues {
            let s = Double(scrollShift(t)) / 270
            return EdgeValues(top: 0.2 - s, right: 0.2, bottom: 0.25 + s, left: 0.2)
        }
        let none = EdgeValues.uniform(0)
        return [
            sequence(
                "Video in a browser window", size: wide, seconds: 8, settle: 3, offCenter: true, truth: { _ in video }
            ) {
                i, _, b in frame(width: wide.w, height: wide.h, t: i, bars: none) { x, y in desktop(x, y, video: b) }
            },
            sequence(
                "Gray pillarbox (60 of 255)", size: ultrawide, seconds: 6, settle: 3,
                truth: { _ in EdgeValues(top: 0, right: pillar, bottom: 0, left: pillar) }
            ) { i, _, b in
                frame(width: ultrawide.w, height: ultrawide.h, t: i, bars: b, barBlack: 60)
            },
            sequence(
                "Dark blue letterbox", size: wide, seconds: 6, settle: 3,
                truth: { _ in EdgeValues(top: letterbox, right: 0, bottom: letterbox, left: 0) }
            ) { i, _, b in
                let top = Int(letterbox * Double(wide.h))
                return frame(width: wide.w, height: wide.h, t: i, bars: b) { _, y in
                    y < top || y >= wide.h - top ? (0.08, 0.1, 0.3) : nil
                }
            },
            sequence(
                "Grainy letterbox (film grain)", size: wide, seconds: 6,
                truth: { _ in EdgeValues(top: letterbox, right: 0, bottom: letterbox, left: 0) }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b, barBlack: 12, barNoise: 30)
            },
            sequence(
                "Video on a dark page (dark theme)", size: wide, seconds: 8, settle: 3, offCenter: true,
                truth: { _ in video }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: none) { x, y in
                    guard let c = desktop(x, y, video: b) else { return nil }
                    return c.0 > 0.8 ? (0.06, 0.06, 0.06) : c
                }
            },
            sequence(
                "Video in a maximized dark browser", size: wide, seconds: 8, settle: 3, offCenter: true,
                truth: { _ in video }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: none) { x, y in
                    let u = Double(x) / Double(wide.w), v = Double(y) / Double(wide.h)
                    if u >= b.left, u < 1 - b.right, v >= b.top, v < 1 - b.bottom { return nil }
                    if v < 0.07 { return (0.16, 0.16, 0.17) }
                    return y % 16 < 3 && u > 0.05 && u < 0.18 ? (0.5, 0.5, 0.5) : (0.06, 0.06, 0.06)
                }
            },
            sequence(
                "Letterboxed film in a window", size: wide, seconds: 8, settle: 3, offCenter: true,
                truth: { _ in EdgeValues(top: 0.28, right: 0.2, bottom: 0.33, left: 0.2) }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: none) { x, y in
                    let v = Double(y) / Double(wide.h)
                    if let c = desktop(x, y, video: video) { return c }
                    return v < b.top || v >= 1 - b.bottom ? (0.0, 0.0, 0.0) : nil
                }
            },
            sequence(
                "Small video in a corner window", size: wide, seconds: 8, settle: 3, offCenter: true,
                truth: { _ in EdgeValues(top: 0.5, right: 0.06, bottom: 0.1, left: 0.56) }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: none) { x, y in
                    let u = Double(x) / Double(wide.w), v = Double(y) / Double(wide.h)
                    if u >= b.left, u < 1 - b.right, v >= b.top, v < 1 - b.bottom { return nil }
                    return desktop(x, y, video: none, windowOnly: true)
                }
            },
            sequence(
                "Animation in a window: still sky, moving ground", size: wide, seconds: 8, settle: 3,
                offCenter: true, truth: { _ in video }
            ) { i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: none) { x, y in
                    if let c = desktop(x, y, video: b) { return c }
                    let v = (Double(y) / Double(wide.h) - b.top) / (1 - b.top - b.bottom)
                    return v < 0.4 ? (0.35 + 0.3 * v, 0.55 + 0.3 * v, 0.9) : nil
                }
            },
            sequence(
                "Video in a window, paused at 4 s", size: wide, seconds: 8, settle: 3,
                offCenter: true, truth: { _ in video }
            ) { i, t, b in
                frame(width: wide.w, height: wide.h, t: t > 4 ? 120 : i, bars: none) { x, y in desktop(x, y, video: b) }
            },
            sequence(
                "Video in a window, page scrolled at 4 s", size: wide, seconds: 9, settle: 3.7,
                offCenter: true, truth: { t in scrolledVideo(t) }
            ) { i, t, _ in
                let shift = scrollShift(t)
                return frame(width: wide.w, height: wide.h, t: i, bars: none) { x, y in
                    let inWindow = x > 48 && x < 432 && y > 35 && y < 254
                    guard inWindow else { return desktop(x, y, video: none, windowOnly: true) }
                    let py = y + shift
                    let v = Double(py) / Double(wide.h), u = Double(x) / Double(wide.w)
                    if u >= video.left, u < 1 - video.right, v >= video.top, v < 1 - video.bottom { return nil }
                    return py % 18 < 6 && x > 70 && x < 400 ? (0.3, 0.3, 0.32) : (0.97, 0.97, 0.98)
                }
            },
            sequence("Full screen: still sky over a moving scene", size: wide, seconds: 6, truth: { _ in none }) {
                i, _, b in
                frame(width: wide.w, height: wide.h, t: i, bars: b) { _, y in
                    y < wide.h / 3 ? (0.45, 0.62, 0.85) : nil
                }
            },
            sequence(
                "Desktop: a spinner and a progress bar", size: wide, seconds: 6, offCenter: true,
                truth: { _ in none }
            ) { i, _, _ in
                frame(width: wide.w, height: wide.h, t: 0, bars: none) { x, y in
                    let dx = Double(x - 240), dy = Double(y - 120)
                    if dx * dx + dy * dy < 144, Int((atan2(dy, dx) + .pi) * 2 + Double(i) * 0.4).isMultiple(of: 3) {
                        return (0.3, 0.3, 0.35)
                    }
                    if y >= 150, y < 156, x >= 140, x < 140 + min(200, i * 2) { return (0.2, 0.5, 1) }
                    return desktop(x, y, video: none, windowOnly: true)
                }
            },
            sequence(
                "Desktop: typing in a document", size: wide, seconds: 6, offCenter: true,
                truth: { _ in none }
            ) {
                i, _, _ in
                let typed = i / 3
                return frame(width: wide.w, height: wide.h, t: 0, bars: none) { x, y in
                    let line = (y - 60) / 12, column = (x - 110) / 6
                    let isText = y >= 60 && y < 220 && x >= 110 && x < 370 && (y - 60) % 12 < 7
                    if isText, line * 43 + column < typed + 200 { return (0.15, 0.15, 0.17) }
                    return desktop(x, y, video: none, windowOnly: true)
                }
            },
            sequence(
                "Desktop: scrolling a page", size: wide, seconds: 6, offCenter: true,
                truth: { _ in none }
            ) {
                i, _, _ in
                frame(width: wide.w, height: wide.h, t: 0, bars: none) { x, y in
                    let scrolled = y + i * 3
                    let isText =
                        y >= 40 && y < 250 && x >= 110 && x < 370 && scrolled % 14 < 8
                        && noise(x / 5, scrolled / 14, 0) > 0.25
                    if isText { return (0.2, 0.2, 0.22) }
                    return desktop(x, y, video: none, windowOnly: true)
                }
            },
        ]
    }

    static func desktop(_ x: Int, _ y: Int, video: EdgeValues, windowOnly: Bool = false) -> (Double, Double, Double)? {
        let u = Double(x) / Double(wide.w), v = Double(y) / Double(wide.h)
        let inVideo = u >= video.left && u < 1 - video.right && v >= video.top && v < 1 - video.bottom
        if !windowOnly, inVideo, video != .uniform(0) { return nil }
        if u > 0.1, u < 0.9, v > 0.06, v < 0.94 {
            if v < 0.13 { return (0.86, 0.86, 0.88) }
            return (0.97, 0.97, 0.98)
        }
        return (0.25 + 0.2 * u, 0.35 + 0.1 * v, 0.55 + 0.1 * u)
    }

    static func run(_ scenario: Scenario) -> Result {
        var area = AutoCaptureArea()
        var result = Result(name: scenario.name)
        var lastTruth: EdgeValues?
        var changeTime = 0.0
        var matched = false
        let tolX = 2.0 / Double(scenario.width), tolY = 2.0 / Double(scenario.height)
        for f in scenario.frames {
            if lastTruth != f.truth {
                if lastTruth != nil, !matched, f.time - changeTime >= scenario.settle {
                    result.worstLatency = .infinity
                }
                lastTruth = f.truth; changeTime = f.time; matched = false
            }
            result.totalFrames += 1
            _ = f.pixels.withUnsafeBytes {
                area.update(
                    bgra: $0.baseAddress!, width: scenario.width, height: scenario.height,
                    bytesPerRow: scenario.width * 4, at: f.time, allowsOffCenter: scenario.allowsOffCenter)
            }
            let got = area.insets
            let within =
                abs(got.top - f.truth.top) <= tolY && abs(got.bottom - f.truth.bottom) <= tolY
                && abs(got.left - f.truth.left) <= tolX && abs(got.right - f.truth.right) <= tolX
            if within, !matched { matched = true; result.worstLatency = max(result.worstLatency, f.time - changeTime) }
            let overcrop =
                got.top - f.truth.top > tolY || got.bottom - f.truth.bottom > tolY
                || got.left - f.truth.left > tolX || got.right - f.truth.right > tolX
            if overcrop { result.falseCrop += 1 }
            if f.time - changeTime >= scenario.settle {
                result.settledFrames += 1
                if within { result.accurate += 1 }
            }
        }
        if !matched, (scenario.frames.last?.time ?? 0) - changeTime >= scenario.settle {
            result.worstLatency = .infinity
        }
        return result
    }

    static func line(_ r: Result) -> String {
        let latency = r.worstLatency.isFinite ? String(format: "%.2f s", r.worstLatency) : "never"
        return r.name.padding(toLength: 48, withPad: " ", startingAt: 0)
            + String(format: "%7.1f %%  %8.2f %%  ", r.accuracy * 100, r.falseCropRate * 100) + latency
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUROLIGHT_BENCHMARK"] != nil))
    func report() {
        let header = "Scenario".padding(toLength: 48, withPad: " ", startingAt: 0) + "accuracy  false crop  latency"
        let rule = String(repeating: "-", count: 88)
        var lines = ["", "Capture-area benchmark", rule, header]
        var results: [Result] = []
        for scenario in Self.scenarios {
            let r = Self.run(scenario)
            results.append(r)
            lines.append(Self.line(r))
        }
        let settled = results.reduce(0) { $0 + $1.settledFrames }, accurate = results.reduce(0) { $0 + $1.accurate }
        let total = results.reduce(0) { $0 + $1.totalFrames }, falseCrops = results.reduce(0) { $0 + $1.falseCrop }
        let overallAccuracy = Double(accurate) / Double(max(settled, 1))
        let overallFalseCrop = Double(falseCrops) / Double(max(total, 1))
        lines.append(rule)
        lines.append(
            String(
                format: "Overall accuracy %.2f %% · false-crop frames %.3f %%",
                overallAccuracy * 100, overallFalseCrop * 100))
        print(lines.joined(separator: "\n"))

        for r in results {
            #expect(r.worstLatency.isFinite, "\(r.name): never matched the truth")
            #expect(r.accuracy >= 0.99, "\(r.name): accuracy \(r.accuracy)")
            #expect(r.falseCrop == 0, "\(r.name): \(r.falseCrop) false-crop frames")
        }
    }
}
