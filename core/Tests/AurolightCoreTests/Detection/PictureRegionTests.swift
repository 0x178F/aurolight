import Testing

@testable import AurolightCore

struct PictureRegionTests {
    let width = 200, height = 120
    let video = (x0: 40, y0: 20, x1: 150, y1: 90)

    func frame(_ t: Int, moving: Bool = true, scroll: Int? = nil) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var c = (200, 205, 215)
                if let scroll {
                    if (y + scroll) % 12 < 4, x > 20, x < 180 { c = (60, 60, 65) }
                } else if moving, x >= video.x0, x < video.x1, y >= video.y0, y < video.y1 {
                    c = ((x * 7 + t * 13) % 256, (y * 5 + t * 29) % 256, (x + y + t * 17) % 256)
                }
                let o = (y * width + x) * 4
                pixels[o] = UInt8(c.2); pixels[o + 1] = UInt8(c.1); pixels[o + 2] = UInt8(c.0)
            }
        }
        return pixels
    }

    func run(seconds: Double, allowsOffCenter: Bool, _ make: (Int) -> [UInt8]) -> EdgeValues? {
        var detector = PictureRegionDetector()
        for i in 0..<Int(seconds * 30) {
            _ = make(i).withUnsafeBytes {
                detector.update(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4, at: Double(i) / 30,
                    allowsOffCenter: allowsOffCenter)
            }
        }
        return detector.insets
    }

    @Test func findsAVideoInAWindow() throws {
        let insets = try #require(run(seconds: 4, allowsOffCenter: true) { frame($0) })
        #expect(abs(insets.left - 40.0 / 200) < 0.01 && abs(insets.right - 50.0 / 200) < 0.01)
        #expect(abs(insets.top - 20.0 / 120) < 0.02 && abs(insets.bottom - 30.0 / 120) < 0.02)
    }

    @Test func pausedPictureIsReleasedAfterIdleTimeEvenWithFewFrames() {
        var detector = PictureRegionDetector()
        func feed(_ pixels: [UInt8], at time: Double) {
            _ = pixels.withUnsafeBytes {
                detector.update(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4, at: time,
                    allowsOffCenter: true)
            }
        }
        for i in 0..<120 { feed(frame(i), at: Double(i) / 30) }
        #expect(detector.insets != nil)
        for k in 1...8 { feed(frame(119), at: 4 + Double(k) * 5) }
        #expect(detector.insets == nil)
    }

    @Test func aStoppedScreenLetsThePictureGoWithoutNewFrames() {
        var detector = PictureRegionDetector()
        for i in 0..<120 {
            _ = frame(i).withUnsafeBytes {
                detector.update(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4, at: Double(i) / 30,
                    allowsOffCenter: true)
            }
        }
        #expect(detector.insets != nil)
        let early = detector.expire(at: 10)
        let late = detector.expire(at: 4 + PictureRegionDetector.idleRelease)
        #expect(!early && late)
        #expect(detector.insets == nil)
    }

    @Test func goingFullScreenDropsAnOffCenterPicture() {
        var detector = PictureRegionDetector()
        for i in 0..<150 {
            _ = frame(i).withUnsafeBytes {
                detector.update(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4, at: Double(i) / 30,
                    allowsOffCenter: i < 120)
            }
            if i == 119 { #expect(detector.insets != nil) }
        }
        #expect(detector.insets == nil)
    }

    @Test func offCenterPictureIsIgnoredBehindAFullScreenWindow() {
        #expect(run(seconds: 4, allowsOffCenter: false) { frame($0) } == nil)
    }

    @Test func findsAFullScreenVideoWithGrayBars() throws {
        let found = run(seconds: 4, allowsOffCenter: false) { t in
            var pixels = frame(t, moving: false)
            for y in 0..<height {
                for x in 0..<width {
                    let o = (y * width + x) * 4
                    let c: (Int, Int, Int) =
                        x < 30 || x >= 170
                        ? (96, 96, 100) : ((x * 7 + t * 13) % 256, (y * 5 + t * 29) % 256, (x + y + t * 17) % 256)
                    pixels[o] = UInt8(c.2); pixels[o + 1] = UInt8(c.1); pixels[o + 2] = UInt8(c.0)
                }
            }
            return pixels
        }
        let insets = try #require(found)
        #expect(abs(insets.left - 0.15) < 0.01 && abs(insets.right - 0.15) < 0.01)
        #expect(insets.top == 0 && insets.bottom == 0)
    }

    @Test func aRepeatedTimestampChangesNothing() {
        var detector = PictureRegionDetector()
        func feed(_ i: Int, at time: Double) {
            _ = frame(i).withUnsafeBytes {
                detector.update(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4, at: time,
                    allowsOffCenter: true)
            }
        }
        for i in 0..<120 { feed(i, at: Double(i) / 30) }
        let found = detector.insets
        feed(119, at: 119.0 / 30)
        feed(120, at: 120.0 / 30)
        #expect(found != nil && detector.insets == found)
    }

    @Test func scrollingIsNotVideo() {
        #expect(run(seconds: 4, allowsOffCenter: true) { frame($0, scroll: $0) } == nil)
    }

    @Test func staticDesktopIsNotCropped() {
        #expect(run(seconds: 4, allowsOffCenter: true) { frame($0, moving: false) } == nil)
    }
}
