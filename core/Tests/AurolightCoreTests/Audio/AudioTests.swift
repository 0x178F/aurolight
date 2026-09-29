import Foundation
import Testing

@testable import AurolightCore

struct AudioTests {
    func tone(_ hz: Double, seconds: Double = 0.5, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * 48_000)).map { Float(sin(2 * .pi * hz * Double($0) / 48_000)) * amplitude }
    }

    @Test func bandsFollowFrequency() {
        var low = AudioBandAnalyzer()
        low.append(tone(80))
        #expect(low.levels.bands(atAge: 0).bass > 0.5)
        #expect(low.levels.bands(atAge: 0).bass > low.levels.bands(atAge: 0).treble * 3)

        var high = AudioBandAnalyzer()
        high.append(tone(5_000))
        #expect(high.levels.bands(atAge: 0).treble > 0.5)
        #expect(high.levels.bands(atAge: 0).treble > high.levels.bands(atAge: 0).bass * 3)
    }

    @Test func silenceStaysDark() {
        var analyzer = AudioBandAnalyzer()
        analyzer.append([Float](repeating: 0, count: 24_000))
        let b = analyzer.levels.bands(atAge: 0)
        #expect(b.bass == 0 && b.mid == 0 && b.treble == 0)
    }

    @Test func historyIsNewestFirstAndBounded() {
        var analyzer = AudioBandAnalyzer()
        let hops = analyzer.append(tone(80, seconds: 3))
        #expect(hops == 3 * 48_000 / AudioBandAnalyzer.hopSize)
        #expect(analyzer.levels.history.count == AudioBandAnalyzer.historyLength)
        analyzer.append([Float](repeating: 0, count: 48_000 / 4))
        let history = analyzer.levels.history
        #expect(history.first!.bass < history.last!.bass)
    }

    @Test func resetKeepsSampleRateAndClearsState() {
        var analyzer = AudioBandAnalyzer(sampleRate: 44_100)
        let hopSeconds = analyzer.hopSeconds
        analyzer.append(tone(80))
        analyzer.append([Float](repeating: 0.1, count: 100))
        analyzer.reset()
        #expect(analyzer.sampleRate == 44_100)
        #expect(analyzer.hopSeconds == hopSeconds)
        #expect(analyzer.levels == .silent)
        #expect(analyzer.pendingCount == 0)
    }

    @Test func partialHopsWait() {
        var analyzer = AudioBandAnalyzer()
        #expect(analyzer.append([Float](repeating: 0.1, count: 300)) == 0)
        #expect(analyzer.pendingCount == 300)
        #expect(analyzer.append([Float](repeating: 0.1, count: 300)) == 1)
        #expect(analyzer.pendingCount == 88)
    }

    @Test func historyLookupAccountsForNewestAge() {
        let history = [AudioLevels.Bands(bass: 1, mid: 0, treble: 0), AudioLevels.Bands(bass: 0, mid: 0, treble: 0)]
        let fresh = AudioLevels(history: history, historyInterval: 0.01, newestAge: 0)
        let late = AudioLevels(history: history, historyInterval: 0.01, newestAge: 0.005)
        // 5 ms ago: halfway to the older entry when the newest is current, still the newest when it is 5 ms old.
        #expect(abs(fresh.bands(atAge: 0.005).bass - 0.5) < 1e-9)
        #expect(late.bands(atAge: 0.005).bass == 1)
        #expect(abs(late.bands(atAge: 0.01).bass - 0.5) < 1e-9)
        #expect(fresh.bands(atAge: 1) == AudioLevels.Bands(bass: 0, mid: 0, treble: 0))
    }
}
