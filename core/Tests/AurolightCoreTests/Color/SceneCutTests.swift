import AurolightCore
import Testing

struct SceneCutTests {
    let black = [RGB](repeating: .black, count: 10)
    let white = [RGB](repeating: RGB(r: 1, g: 1, b: 1), count: 10)

    @Test func smallChangesAreNoCut() {
        let dimmed = [RGB](repeating: RGB(r: 0.9, g: 0.9, b: 0.9), count: 10)
        #expect(!ScreenSampler.isSceneCut(from: white, to: white))
        #expect(!ScreenSampler.isSceneCut(from: white, to: dimmed))
    }

    @Test func largeChangeIsCut() {
        #expect(ScreenSampler.isSceneCut(from: black, to: white))
    }

    @Test func emptyOrMismatchedFramesAreNoCut() {
        #expect(!ScreenSampler.isSceneCut(from: [], to: []))
        #expect(!ScreenSampler.isSceneCut(from: black, to: Array(white.prefix(5))))
    }
}
