import Testing

@testable import AurolightCore

struct BlackBarTests {
    func frame(width: Int, height: Int, top: Int, bottom: Int, left: Int, right: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in top..<(height - bottom) {
            for x in left..<(width - right) {
                let o = (y * width + x) * 4
                pixels[o] = 120; pixels[o + 1] = 90; pixels[o + 2] = 60; pixels[o + 3] = 255
            }
        }
        return pixels
    }

    func read(_ pixels: [UInt8], _ width: Int, _ height: Int) -> BarReading {
        pixels.withUnsafeBytes {
            BlackBarDetector.read(bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4)
        }
    }

    let letterbox = BarReading(top: .bar(0.12), right: .none, bottom: .bar(0.12), left: .none)
    let clear = BarReading(top: .none, right: .none, bottom: .none, left: .none)

    func feed(_ tracker: inout BlackBarTracker, _ reading: BarReading, from start: Double, for seconds: Double) {
        var t = start
        while t < start + seconds {
            _ = tracker.update(with: reading, at: t)
            t += 1.0 / 30
        }
    }

    @Test func findsLetterboxBars() {
        let r = read(frame(width: 400, height: 200, top: 24, bottom: 24, left: 0, right: 0), 400, 200)
        #expect(r == letterbox)
    }

    @Test func findsPillarboxAndNotchBand() {
        let r = read(frame(width: 400, height: 200, top: 7, bottom: 0, left: 50, right: 50), 400, 200)
        #expect(r.top == .bar(0.035) && r.bottom == .none)
        #expect(r.left == .bar(0.125) && r.right == .bar(0.125))
    }

    @Test func findsBarsWithFilmGrain() {
        var pixels = frame(width: 400, height: 200, top: 24, bottom: 24, left: 0, right: 0)
        for y in 0..<200 where y < 24 || y >= 176 {
            for x in 0..<400 {
                let grain = UInt8(truncatingIfNeeded: (x &* 7919 ^ y &* 104_729) % 31)
                let o = (y * 400 + x) * 4
                pixels[o] = grain / 2 + 4; pixels[o + 1] = grain / 2 + 4; pixels[o + 2] = grain / 2 + 4
            }
        }
        #expect(read(pixels, 400, 200) == letterbox)
    }

    func letterbox(top: (UInt8, UInt8, UInt8), bottom: (UInt8, UInt8, UInt8)) -> [UInt8] {
        var pixels = frame(width: 400, height: 200, top: 24, bottom: 24, left: 0, right: 0)
        for y in 24..<176 {
            let c = y < 60 ? top : y >= 140 ? bottom : (120, 90, 60)
            for x in 0..<400 {
                let o = (y * 400 + x) * 4
                pixels[o] = c.0; pixels[o + 1] = c.1; pixels[o + 2] = c.2
            }
        }
        return pixels
    }

    @Test func darkButColoredPictureEndsTheBar() {
        let r = read(letterbox(top: (80, 23, 45), bottom: (120, 90, 60)), 400, 200)
        #expect(r.top == .bar(0.12) && r.bottom == .bar(0.12))
    }

    @Test func darkEdgeIsConfirmedByTheOppositeBar() {
        let r = read(letterbox(top: (120, 90, 60), bottom: (18, 12, 8)), 400, 200)
        #expect(r.top == .bar(0.12) && r.bottom == .likelyBar(0.12))
        let validated = BlackBarTracker.validate(r)
        #expect(validated.top == .bar(0.12) && validated.bottom == .bar(0.12))
    }

    @Test func narrowCaptionInTheBarKeepsIt() {
        var pixels = frame(width: 400, height: 200, top: 24, bottom: 24, left: 0, right: 0)
        for y in 186..<192 {
            for x in 160..<240 {
                let o = (y * 400 + x) * 4
                pixels[o] = 235; pixels[o + 1] = 235; pixels[o + 2] = 235
            }
        }
        #expect(read(pixels, 400, 200) == letterbox)
    }

    @Test func pictureReachingOneEdgeReleasesItAlone() {
        var tracker = BlackBarTracker()
        feed(&tracker, letterbox, from: 0, for: 3)
        _ = tracker.update(with: BarReading(top: .none, right: .none, bottom: .unknown, left: .none), at: 3.1)
        #expect(tracker.insets.top == 0 && tracker.insets.bottom == 0.12)
    }

    @Test func aSlowGradientIsNotConfirmedByARealBar() {
        var pixels = frame(width: 200, height: 100, top: 0, bottom: 8, left: 0, right: 0)
        for y in 0..<30 {
            let v = UInt8(2 + y * 3 / 4)
            for x in 0..<200 {
                let o = (y * 200 + x) * 4
                pixels[o] = v; pixels[o + 1] = v; pixels[o + 2] = v
            }
        }
        let validated = BlackBarTracker.validate(read(pixels, 200, 100))
        if case .bar = validated.top { Issue.record("gradient cropped: \(validated.top)") }
    }

    @Test func likelyBarsAloneAreNotBars() {
        let reading = BarReading(top: .likelyBar(0.12), right: .none, bottom: .likelyBar(0.12), left: .none)
        #expect(BlackBarTracker.validate(reading).top == .unknown)
    }

    @Test func noBarsOnAFullPicture() {
        #expect(read(frame(width: 200, height: 100, top: 0, bottom: 0, left: 0, right: 0), 200, 100) == clear)
    }

    @Test func toleratesAFewBrightPixelsInABar() {
        var pixels = frame(width: 400, height: 200, top: 20, bottom: 0, left: 0, right: 0)
        pixels[(5 * 400 + 200) * 4 + 2] = 255
        #expect(read(pixels, 400, 200).top == .bar(0.1))
    }

    @Test func skipsSubtitlesInsideABar() {
        var pixels = frame(width: 400, height: 200, top: 0, bottom: 30, left: 0, right: 0)
        for y in 185...186 {
            for x in 120..<280 {
                let o = (y * 400 + x) * 4
                pixels[o] = 230; pixels[o + 1] = 230; pixels[o + 2] = 230
            }
        }
        #expect(read(pixels, 400, 200).bottom == .bar(0.15))
    }

    @Test func gradientIsNotABar() {
        var pixels = frame(width: 200, height: 100, top: 0, bottom: 0, left: 0, right: 0)
        for y in 0..<30 {
            let v = UInt8(2 + y * 3 / 4)
            for x in 0..<200 {
                let o = (y * 200 + x) * 4
                pixels[o] = v; pixels[o + 1] = v; pixels[o + 2] = v
            }
        }
        let reading = read(pixels, 200, 100)
        if case .bar = reading.top { Issue.record("gradient read as a bar") }
        #expect(BlackBarTracker.validate(reading).top == .unknown)
    }

    @Test func centeredCreditsAreNotPillarbox() {
        var pixels = [UInt8](repeating: 0, count: 400 * 200 * 4)
        for y in 0..<200 where y % 10 < 3 {
            for x in 100..<300 where x % 4 < 2 {
                let o = (y * 400 + x) * 4
                pixels[o] = 240; pixels[o + 1] = 240; pixels[o + 2] = 240
            }
        }
        let r = read(pixels, 400, 200)
        #expect(r.left != .bar(0.25) && r.right != .bar(0.25))
        #expect(BlackBarTracker.validate(r).left == .unknown)
    }

    @Test func blackFrameIsUnknown() {
        let black = [UInt8](repeating: 0, count: 200 * 100 * 4)
        #expect(read(black, 200, 100) == .unknown)
    }

    @Test func tinyFrameIsUnknown() {
        #expect(read(frame(width: 16, height: 16, top: 2, bottom: 2, left: 0, right: 0), 16, 16) == .unknown)
    }

    @Test func growsOnlyAfterSustainedEvidence() {
        var tracker = BlackBarTracker()
        let grow = BlackBarTracker.growSeconds
        feed(&tracker, letterbox, from: 0, for: 0.75 * grow)
        #expect(tracker.insets == .uniform(0))
        feed(&tracker, letterbox, from: 0.75 * grow, for: 0.5 * grow)
        #expect(tracker.insets == EdgeValues(top: 0.12, right: 0, bottom: 0.12, left: 0))
    }

    @Test func anEdgeWobblingBetweenRowsDoesNotFlicker() {
        var tracker = BlackBarTracker()
        feed(&tracker, letterbox, from: 0, for: 2)
        let row = 1.0 / 270
        var changes = 0
        for i in 0..<300 {
            let bar = 0.12 - (i.isMultiple(of: 3) ? row : 0)
            let reading = BarReading(top: .bar(bar), right: .none, bottom: .bar(0.12), left: .none)
            if tracker.update(with: reading, at: 2 + Double(i) / 30) { changes += 1 }
        }
        #expect(changes <= 1)
    }

    @Test func briefRisesInTheBarNeverCrop() {
        var tracker = BlackBarTracker()
        var changes = 0
        for i in 0..<600 {
            let top = i.isMultiple(of: 40) ? 0.015 : i.isMultiple(of: 7) ? 0.005 : 0
            let reading = BarReading(top: top > 0 ? .bar(top) : .none, right: .none, bottom: .none, left: .none)
            if tracker.update(with: reading, at: Double(i) / 30) { changes += 1 }
        }
        #expect(tracker.insets == .uniform(0) && changes == 0)
    }

    @Test func stalledCaptureCannotConfirm() {
        // Each gap counts for at most maxStep, so long stalls never add up to growSeconds.
        var tracker = BlackBarTracker()
        for i in 0..<BlackBarTracker.growFrames {
            _ = tracker.update(with: letterbox, at: Double(i) * 5)
        }
        #expect(tracker.insets == .uniform(0))
    }

    @Test func unknownKeepsBarsButClearsEvidence() {
        var tracker = BlackBarTracker()
        feed(&tracker, letterbox, from: 0, for: 3)
        // Together the two stretches would confirm, but the blackout in between restarts the evidence.
        let grow = BlackBarTracker.growSeconds
        let wider = BarReading(top: .bar(0.2), right: .none, bottom: .bar(0.2), left: .none)
        feed(&tracker, wider, from: 3, for: 0.75 * grow)
        feed(&tracker, .unknown, from: 3 + 0.75 * grow, for: 0.5)
        #expect(tracker.insets.top == 0.12)
        feed(&tracker, wider, from: 3.5 + 0.75 * grow, for: 0.5 * grow)
        #expect(tracker.insets.top == 0.12)
    }

    @Test func shrinksQuickly() {
        var tracker = BlackBarTracker()
        feed(&tracker, letterbox, from: 0, for: 3)
        feed(&tracker, clear, from: 3, for: 0.15)
        #expect(tracker.insets == .uniform(0))
    }

    @Test func barsDroppedByOneMisreadFrameReturnAtOnce() {
        var tracker = BlackBarTracker()
        feed(&tracker, letterbox, from: 0, for: 3)
        _ = tracker.update(with: clear, at: 3)
        #expect(tracker.insets == .uniform(0))
        _ = tracker.update(with: letterbox, at: 3.05)
        #expect(tracker.insets.top == 0.12)
    }

    @Test func rejectsAsymmetricAxis() {
        var tracker = BlackBarTracker()
        feed(&tracker, BarReading(top: .bar(0.3), right: .none, bottom: .none, left: .none), from: 0, for: 4)
        #expect(tracker.insets == .uniform(0))
    }

    @Test func acceptsTheNotchBand() {
        var tracker = BlackBarTracker()
        feed(&tracker, BarReading(top: .bar(0.033), right: .none, bottom: .none, left: .none), from: 0, for: 3)
        #expect(tracker.insets.top == 0.033)
    }

    @Test func edgesConfirmIndependently() {
        var tracker = BlackBarTracker()
        var t = 0.0
        for i in 0..<90 {
            let flicker: EdgeReading = i.isMultiple(of: 2) ? .bar(0.25) : .none
            _ = tracker.update(
                with: BarReading(top: flicker, right: .bar(0.125), bottom: flicker, left: .bar(0.125)), at: t)
            t += 1.0 / 30
        }
        #expect(tracker.insets.left == 0.125 && tracker.insets.right == 0.125)
        #expect(tracker.insets.top == 0)
    }

    @Test func validateToleratesSmallMismatchOnly() {
        let close = BlackBarTracker.validate(BarReading(top: .bar(0.12), right: .none, bottom: .bar(0.13), left: .none))
        #expect(close.top == .bar(0.12) && close.bottom == .bar(0.13))
        let apart = BlackBarTracker.validate(
            BarReading(top: .bar(0.12), right: .none, bottom: .bar(0.135), left: .none))
        #expect(apart.top == .unknown && apart.bottom == .unknown)
    }
}
