import Testing

@testable import AurolightCore

struct CellSamplesTests {
    func samples(_ levels: [UInt8]) -> CellSamples {
        var s = CellSamples()
        for (i, v) in levels.enumerated() { s.set(i, blue: v, green: v, red: v) }
        return s
    }

    @Test func storesEachSampleAsLuma() {
        var s = samples([10, 20, 30, 40])
        #expect((0..<4).map { s[$0] } == [10, 20, 30, 40])
        s.set(2, blue: 200, green: 200, red: 200)
        #expect((0..<4).map { s[$0] } == [10, 20, 200, 40])
        #expect(s.mean == 67 && s.spread == 190)
    }

    @Test func matchesWithinTolerance() {
        #expect(samples([100, 100, 100, 100]).matches(samples([104, 96, 100, 100]), within: 5))
        #expect(!samples([100, 100, 100, 100]).matches(samples([100, 100, 100, 110]), within: 5))
    }

    @Test func clippedOnlyWhenEverySampleIs() {
        #expect(samples([255, 255, 255, 255]).isClipped(dark: 4, light: 250))
        #expect(samples([0, 2, 1, 0]).isClipped(dark: 4, light: 250))
        #expect(!samples([255, 255, 255, 120]).isClipped(dark: 4, light: 250))
    }

    @Test func packedColorChannelsAndNeutrality() {
        let warm = PackedColor(blue: 60, green: 190, red: 240)
        #expect(warm.blue == 60 && warm.green == 190 && warm.red == 240)
        #expect(!warm.isNeutral(spread: 24))
        #expect(PackedColor(blue: 230, green: 235, red: 240).isNeutral(spread: 24))
        #expect(warm.matches(PackedColor(blue: 64, green: 186, red: 240), within: 5))
        #expect(!warm.matches(PackedColor(blue: 70, green: 190, red: 240), within: 5))
        #expect(PackedColor(blue: 255, green: 255, red: 255).luma == 255)
    }
}
