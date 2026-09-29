import Foundation
import Testing

@testable import AurolightCore

/// Real footage from Blender's open movies, decoded by ffmpeg. Slow (several minutes), so it only runs on request:
/// `make benchmark-footage` (downloads the movies once, then sets AUROLIGHT_FOOTAGE).
@Suite(.serialized)
struct FootageBenchmark {
    static let directory = ProcessInfo.processInfo.environment["AUROLIGHT_FOOTAGE"].map(URL.init(fileURLWithPath:))
    static var isEnabled: Bool { directory != nil }

    /// Frames of a movie through an ffmpeg filter graph, as BGRA at 30 fps.
    final class Movie {
        let width: Int, height: Int
        private let process = Process()
        private let output: FileHandle

        init(_ name: String, filter: String = "[0:v]null", width: Int = 480, height: Int = 270) throws {
            self.width = width
            self.height = height
            let url = try #require(FootageBenchmark.directory).appendingPathComponent(name)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "ffmpeg", "-v", "error", "-i", url.path, "-filter_complex",
                "\(filter),scale=\(width):\(height),format=bgra", "-r", "30", "-f", "rawvideo", "-",
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            output = pipe.fileHandleForReading
            try process.run()
        }

        deinit {
            // Closing the pipe first: ffmpeg flushes on SIGTERM and would block on a full pipe.
            try? output.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        func next() -> [UInt8]? {
            var frame = [UInt8]()
            frame.reserveCapacity(width * height * 4)
            while frame.count < width * height * 4 {
                let chunk = output.readData(ofLength: width * height * 4 - frame.count)
                if chunk.isEmpty { return nil }
                frame.append(contentsOf: chunk)
            }
            return frame
        }
    }

    struct Scenario {
        let name: String
        let movie: String
        var filter = "[0:v]null"
        var height = 270
        let truth: EdgeValues
        var allowsOffCenter = false
        /// Just under the measured accuracy, so a regression fails. Misses are the first seconds before the
        /// picture moves or is confirmed.
        var minAccuracy = 0.99
    }

    /// The movie in a browser-like window: toolbar, text lines below the video.
    private static func window(dark: Bool, _ movie: String = "[0:v]") -> String {
        let (page, bar, text) = dark ? ("0x0f0f0f", "0x212121", "0xaaaaaa") : ("0xf2f2f5", "0xdddde2", "0x55555a")
        return "color=c=\(page):s=1920x1080,drawbox=x=0:y=0:w=1920:h=70:c=\(bar):t=fill,"
            + "drawbox=x=384:y=900:w=900:h=14:c=\(text):t=fill,drawbox=x=384:y=940:w=700:h=14:c=\(text):t=fill[page];"
            + "\(movie)scale=1152:648[video];[page][video]overlay=384:216:shortest=1"
    }

    static let scenarios: [Scenario] = {
        let sintelBars = 132.0 / 1080, tosBars = 93.0 / 720
        return [
            Scenario(
                name: "Sintel, full screen", movie: "sintel_trailer.mp4",
                truth: EdgeValues(top: sintelBars, right: 0, bottom: sintelBars, left: 0)),
            Scenario(
                name: "Sintel on a 21:9 display", movie: "sintel_trailer.mp4",
                filter: "[0:v]scale=1920:1080,pad=2560:1080:320:0:black", height: 202,
                truth: EdgeValues(top: sintelBars, right: 0.125, bottom: sintelBars, left: 0.125)),
            Scenario(name: "Big Buck Bunny, full screen", movie: "bbb_trailer.mov", truth: .uniform(0)),
            Scenario(
                name: "Big Buck Bunny in a light window", movie: "bbb_trailer.mov", filter: window(dark: false),
                truth: .uniform(0.2), allowsOffCenter: true, minAccuracy: 0.95),
            Scenario(
                name: "Sintel in a dark window", movie: "sintel_trailer.mp4", filter: window(dark: true),
                truth: EdgeValues(
                    top: (216 + 132 * 0.6) / 1080, right: 0.2, bottom: (216 + 132 * 0.6) / 1080, left: 0.2),
                allowsOffCenter: true, minAccuracy: 0.96),
            Scenario(
                name: "Tears of Steel, letterboxed", movie: "tos.mov", filter: "[0:v]pad=1280:720:0:93:black",
                truth: EdgeValues(top: tosBars, right: 0, bottom: tosBars, left: 0), minAccuracy: 0.98),
            Scenario(
                name: "Tears of Steel on a 21:9 display", movie: "tos.mov", filter: "[0:v]pad=1280:536:0:1:black",
                height: 201, truth: .uniform(0)),
            Scenario(
                name: "Tears of Steel in a dark window", movie: "tos.mov",
                filter: window(dark: true, "[0:v]pad=1280:720:0:93:black,"),
                truth: EdgeValues(
                    top: (216 + 93 * 0.9) / 1080, right: 0.2, bottom: (216 + 93 * 0.9) / 1080, left: 0.2),
                allowsOffCenter: true, minAccuracy: 0.97),
            Scenario(name: "Elephants Dream, full screen", movie: "ed.mov", truth: .uniform(0)),
            Scenario(
                name: "Elephants Dream, pillarboxed", movie: "ed.mov", filter: "[0:v]pad=645:270:82:0:black",
                height: 201, truth: EdgeValues(top: 0, right: 83.0 / 645, bottom: 0, left: 82.0 / 645)),
        ]
    }()

    @Test(.enabled(if: isEnabled))
    func captureArea() throws {
        let rule = String(repeating: "-", count: 80)
        var lines = ["", "Footage: automatic capture area (accuracy after 4 s, shifts after locking on)", rule]
        for scenario in Self.scenarios {
            let movie = try Movie(scenario.movie, filter: scenario.filter, height: scenario.height)
            let tolerance = (x: 2.0 / Double(movie.width), y: 2.0 / Double(movie.height))
            var area = AutoCaptureArea()
            var frames = 0, settled = 0, accurate = 0, falseCrop = 0, shifts = 0
            var matched = false, last = area.insets
            while let pixels = movie.next() {
                let time = Double(frames) / 30
                pixels.withUnsafeBytes { raw in
                    _ = area.update(
                        bgra: raw.baseAddress!, width: movie.width, height: movie.height, bytesPerRow: movie.width * 4,
                        at: time, allowsOffCenter: scenario.allowsOffCenter)
                }
                let got = area.insets, truth = scenario.truth
                let edges = [
                    (got.top, truth.top, tolerance.y), (got.bottom, truth.bottom, tolerance.y),
                    (got.left, truth.left, tolerance.x), (got.right, truth.right, tolerance.x),
                ]
                if edges.contains(where: { $0.0 - $0.1 > $0.2 }) { falseCrop += 1 }
                if got != last {
                    if matched { shifts += 1 }
                    last = got
                }
                if edges.allSatisfy({ abs($0.0 - $0.1) <= $0.2 }) { matched = true }
                if time > 4 {
                    settled += 1
                    if edges.allSatisfy({ abs($0.0 - $0.1) <= $0.2 }) { accurate += 1 }
                }
                frames += 1
            }
            let accuracy = Double(accurate) / Double(max(settled, 1))
            lines.append(
                scenario.name.padding(toLength: 36, withPad: " ", startingAt: 0)
                    + String(
                        format: "%6d frames   %5.1f %%   false crop %d   shifts %d", frames, accuracy * 100, falseCrop,
                        shifts))
            #expect(frames > 0, "\(scenario.name): no frames decoded")
            #expect(accuracy >= scenario.minAccuracy, "\(scenario.name): accuracy \(accuracy)")
            #expect(falseCrop == 0, "\(scenario.name): \(falseCrop) false-crop frames")
            #expect(shifts <= 2, "\(scenario.name): the area moved \(shifts) times after locking on")
        }
        lines.append(rule)
        print(lines.joined(separator: "\n"))
    }

    /// A bright channel logo top right and a HUD bar bottom left, drawn over the movie.
    private static let overlays =
        "drawbox=x=1650:y=60:w=180:h=70:c=white:t=fill,drawbox=x=1668:y=78:w=144:h=34:c=0x202020:t=fill,"
        + "drawbox=x=60:y=990:w=420:h=44:c=0x1a1a1a:t=fill,drawbox=x=66:y=996:w=300:h=32:c=0x30d050:t=fill"

    @Test(.enabled(if: isEnabled), arguments: ["bbb_trailer.mov", "tos.mov"])
    func overlays(movie name: String) throws {
        let fit = name == "tos.mov" ? "crop=950:534,scale=1920:1080" : "scale=1920:1080"
        let clean = try Movie(name, filter: "[0:v]\(fit)")
        let covered = try Movie(name, filter: "[0:v]\(fit),\(Self.overlays)")
        let layout = LEDLayout(top: 48, right: 27, bottom: 48, left: 27)
        let slots = layout.slots()
        let near = slots.indices.filter { i in
            let s = slots[i]
            return (s.edge == .top && s.position > 0.8) || (s.edge == .right && s.position < 0.2)
                || (s.edge == .bottom && s.position < 0.3) || (s.edge == .left && s.position > 0.85)
        }
        var reference = ScreenSampler(), untracked = ScreenSampler(), tracked = ScreenSampler()
        reference.tracksOverlays = false
        untracked.tracksOverlays = false
        var errors: (off: [Double], on: [Double]) = ([], [])
        var frame = 0
        while let a = clean.next(), let b = covered.next() {
            let truth = Self.sample(&reference, a, layout)
            let off = Self.sample(&untracked, b, layout), on = Self.sample(&tracked, b, layout)
            if frame > 300 {
                for i in near {
                    errors.off.append(OverlayBenchmark.distance(truth[i], off[i]))
                    errors.on.append(OverlayBenchmark.distance(truth[i], on[i]))
                }
            }
            frame += 1
        }
        let off = Self.mean(errors.off), on = Self.mean(errors.on)
        print(
            String(
                format: "Footage: overlays over %@, LED error near them: %.3f untracked, %.3f tracked", name, off, on))
        #expect(on <= 0.5 * off, "\(name): error only down to \(on) from \(off)")
    }

    @Test(.enabled(if: isEnabled), arguments: ["bbb_trailer.mov", "sintel_trailer.mp4", "tos.mov", "ed.mov"])
    func trackingLeavesCleanFootageAlone(movie name: String) throws {
        let movie = try Movie(name)
        let layout = LEDLayout(top: 48, right: 27, bottom: 48, left: 27)
        var untracked = ScreenSampler(), tracked = ScreenSampler()
        untracked.tracksOverlays = false
        var changed = 0, frames = 0
        while let pixels = movie.next() {
            let a = Self.sample(&untracked, pixels, layout), b = Self.sample(&tracked, pixels, layout)
            if a.indices.contains(where: { OverlayBenchmark.distance(a[$0], b[$0]) > 0.02 }) { changed += 1 }
            frames += 1
        }
        print("Footage: tracking changed \(changed) of \(frames) frames of \(name)")
        #expect(changed == 0, "\(name): tracking changed \(changed) frames")
    }

    /// How colorful the strip's light is next to the screen's (Oklab chroma of linear light, brightness factored out):
    /// Natural should match, Vivid exceed it.
    @Test(.enabled(if: isEnabled))
    func colorfulness() throws {
        let movie = try Movie("sintel_trailer.mp4")
        let layout = LEDLayout(top: 48, right: 27, bottom: 48, left: 27)
        var sampler = ScreenSampler()
        let natural = ColorSettings()
        var vivid = ColorSettings()
        vivid.select(.vivid)
        func chroma(_ c: RGB) -> Double {
            let peak = max(c.r, c.g, c.b)
            let (_, a, b) = Oklab.fromLinear(r: c.r / peak, g: c.g / peak, b: c.b / peak)
            return (a * a + b * b).squareRoot()
        }
        var ratios: (natural: [Double], vivid: [Double]) = ([], [])
        var frame = 0
        while let pixels = movie.next() {
            let colors = Self.sample(&sampler, pixels, layout)
            frame += 1
            guard frame.isMultiple(of: 15) else { continue }
            for c in colors {
                let screen = RGB(r: SRGB.decode(c.r), g: SRGB.decode(c.g), b: SRGB.decode(c.b))
                guard max(screen.r, screen.g, screen.b) > 0.02, chroma(screen) > 0.03 else { continue }
                ratios.natural.append(chroma(ColorProcessor.finalize(c, natural)) / chroma(screen))
                ratios.vivid.append(chroma(ColorProcessor.finalize(c, vivid)) / chroma(screen))
            }
        }
        let median = { (values: [Double]) in values.sorted()[values.count / 2] }
        let (n, v) = (median(ratios.natural), median(ratios.vivid))
        print(String(format: "Footage: strip colorfulness next to the screen: Natural %.2f, Vivid %.2f", n, v))
        #expect((0.95...1.1).contains(n), "Natural \(n)")
        #expect(v > 1.2, "Vivid \(v)")
    }

    /// Everything the app does per captured frame, on decoded frames held in memory. At 30 fps the budget is 33 ms.
    @Test(.enabled(if: isEnabled))
    func costPerFrame() throws {
        let movie = try Movie("tos.mov", filter: "[0:v]trim=start=120:duration=20,setpts=PTS-STARTPTS")
        var frames: [[UInt8]] = []
        while let pixels = movie.next() { frames.append(pixels) }
        var layout = LEDLayout(top: 48, right: 27, bottom: 48, left: 27)
        var area = AutoCaptureArea(), sampler = ScreenSampler(), renderer = LightFrameRenderer()
        let clock = ContinuousClock()
        var costs: [Duration] = []
        for (i, pixels) in frames.enumerated() {
            let time = Double(i) / 30
            costs.append(
                clock.measure {
                    let samples = pixels.withUnsafeBytes { raw -> [RGB] in
                        _ = area.update(
                            bgra: raw.baseAddress!, width: 480, height: 270, bytesPerRow: 480 * 4, at: time,
                            allowsOffCenter: false)
                        layout.insets = area.insets
                        return sampler.sample(
                            bgra: raw.baseAddress!, width: 480, height: 270, bytesPerRow: 480 * 4, layout: layout,
                            immersion: 0.4)
                    }
                    _ = renderer.render(
                        .init(
                            layout: layout, color: ColorSettings(), effects: EffectSettings(mode: .screen),
                            samples: samples, time: time))
                })
        }
        let ms = costs.map { $0 / .milliseconds(1) }.sorted()
        let mean = ms.reduce(0, +) / Double(ms.count), p99 = ms[ms.count * 99 / 100]
        print(
            String(
                format:
                    "Footage: cost per frame over %d frames: mean %.2f ms, p99 %.2f ms (%.1f %% of one core at 30 fps)",
                ms.count, mean, p99, mean * 30 / 10))
        #expect(mean < 2, "mean \(mean) ms per frame")
        #expect(p99 < 8, "p99 \(p99) ms per frame")
    }

    private static func sample(_ sampler: inout ScreenSampler, _ pixels: [UInt8], _ layout: LEDLayout) -> [RGB] {
        pixels.withUnsafeBytes {
            sampler.sample(
                bgra: $0.baseAddress!, width: 480, height: 270, bytesPerRow: 480 * 4, layout: layout, immersion: 0.4)
        }
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(max(values.count, 1))
    }
}
