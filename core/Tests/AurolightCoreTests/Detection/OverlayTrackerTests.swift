import Testing

@testable import AurolightCore

struct OverlayTrackerTests {
    let width = 200, height = 120

    func frame(_ t: Int, hud: Bool = true, flat: Bool = false, sky: Bool = false) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var c = ((x * 3 + t * 11) % 256, (y * 4 + t * 7) % 256, (x + y + t * 5) % 256)
                if sky, y < height * 2 / 5 { c = (110, 160, 215) }
                if hud, x >= 8, x < 60, y >= 104, y < 112 {
                    let digit = !flat && x >= 10 && x < 30 && y >= 106 && y < 110 && x % 4 < 2
                    c = digit ? (250, 250, 250) : (230, 20, 20)
                }
                let o = (y * width + x) * 4
                pixels[o] = UInt8(c.2); pixels[o + 1] = UInt8(c.1); pixels[o + 2] = UInt8(c.0)
            }
        }
        return pixels
    }

    var hudCells: [Int] { (2..<15).flatMap { x in (26..<28).map { y in y * (width / 4) + x } } }

    func feed(
        _ tracker: inout OverlayTracker, _ frames: Range<Int>,
        area: NormRect = NormRect(x: 0, y: 0, width: 1, height: 1),
        _ make: (Int) -> [UInt8]
    ) {
        for t in frames {
            var grid = ScreenSampler.Grid()
            make(t).withUnsafeBytes {
                grid.load(bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4)
            }
            tracker.apply(to: &grid, area: area)
        }
    }

    func run(_ frames: Int, _ make: (Int) -> [UInt8]) -> (hud: Double, total: Double) {
        var tracker = OverlayTracker()
        feed(&tracker, 0..<frames, make)
        let hud = Double(hudCells.filter { tracker.mask[$0] }.count) / Double(hudCells.count)
        return (hud, Double(tracker.mask.filter { $0 }.count) / Double(tracker.mask.count))
    }

    @Test func learnsAStillHUDOverAMovingPicture() {
        let masked = run(150) { frame($0) }
        #expect(masked.hud == 1)
        #expect(masked.total < 0.05)
    }

    @Test func featurelessStillPatchIsPicture() {
        #expect(run(150) { frame($0, flat: true) }.total == 0)
    }

    @Test func pausedPictureTeachesNothing() {
        #expect(run(150) { _ in frame(40) }.total == 0)
    }

    @Test func largeStillAreasArePicture() {
        let masked = run(150) { frame($0, sky: true) }
        #expect(masked.hud == 1)
        #expect(masked.total < 0.05)
    }

    @Test func aHUDThatGoesAwayIsReleasedAtOnce() {
        var tracker = OverlayTracker()
        feed(&tracker, 0..<150) { frame($0) }
        #expect(hudCells.allSatisfy { tracker.mask[$0] })
        feed(&tracker, 150..<151) { frame($0, hud: false) }
        #expect(!hudCells.contains { tracker.mask[$0] })
    }

    @Test func learnsAHUDInASmallWindowedVideo() {
        let video = NormRect(x: 0, y: 0.6, width: 0.4, height: 0.4)
        func small(_ t: Int) -> [UInt8] {
            var pixels = frame(t, hud: false)
            for y in 0..<height {
                for x in 0..<width {
                    let o = (y * width + x) * 4
                    if x >= width * 2 / 5 || y < height * 3 / 5 {
                        pixels[o] = 230; pixels[o + 1] = 230; pixels[o + 2] = 235
                    } else if x >= 8, x < 24, y >= 104, y < 112 {
                        let digit = x >= 12 && x < 18 && y >= 106 && y < 110 && x % 4 < 2
                        pixels[o] = digit ? 250 : 20
                        pixels[o + 1] = digit ? 250 : 20
                        pixels[o + 2] = digit ? 250 : 230
                    }
                }
            }
            return pixels
        }
        let hud = (2..<6).flatMap { x in (26..<28).map { y in y * (width / 4) + x } }
        var scoped = OverlayTracker(), whole = OverlayTracker()
        feed(&scoped, 0..<150, area: video) { small($0) }
        feed(&whole, 0..<150) { small($0) }
        #expect(hud.allSatisfy { scoped.mask[$0] })
        #expect(!hud.contains { whole.mask[$0] })
    }
}
