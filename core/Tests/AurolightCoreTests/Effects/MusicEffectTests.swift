import Foundation
import Testing

@testable import AurolightCore

struct MusicEffectTests {
    let layout = LEDLayout(top: 4, right: 2, bottom: 4, left: 2)

    @Test func musicScrollEntersAtBottomCenter() {
        let l = LEDLayout(top: 10, right: 6, bottom: 10, left: 6)
        let slots = l.slots()
        let loud = AudioLevels.Bands(bass: 1, mid: 0, treble: 0)
        let history = Array(repeating: loud, count: 5) + Array(repeating: .zero, count: 195)
        let audio = AudioLevels(history: history, historyInterval: 0.01)
        let colors = EffectRenderer.colors(for: EffectSettings(mode: .music), layout: l, time: 0, audio: audio)!
        func brightness(_ c: RGB) -> Double { max(c.r, c.g, c.b) }
        let bottomCenter = zip(slots, colors).filter { $0.0.edge == .bottom && abs($0.0.position - 0.5) < 0.1 }
        let top = zip(slots, colors).filter { $0.0.edge == .top }
        #expect(bottomCenter.map { brightness($0.1) }.min()! > 0.3)
        #expect(top.map { brightness($0.1) }.max()! < 0.1)
        let c = bottomCenter[0].1
        #expect(c.r > c.g && c.g > c.b)
    }

    @Test func musicIsMirrored() {
        let l = LEDLayout(top: 10, right: 6, bottom: 10, left: 6)
        let slots = l.slots()
        let history = (0..<200).map { i in
            AudioLevels.Bands(bass: Double(i % 7) / 7, mid: Double(i % 5) / 5, treble: 0.3)
        }
        let audio = AudioLevels(history: history, historyInterval: 0.01)
        let colors = EffectRenderer.colors(for: EffectSettings(mode: .music), layout: l, time: 0, audio: audio)!
        for (i, slot) in slots.enumerated() where slot.edge == .left {
            let j = slots.firstIndex { $0.edge == .right && abs($0.position - slot.position) < 1e-9 }!
            #expect(colors[i] == colors[j])
        }
    }

    @Test func musicIsDimInSilence() {
        let colors = EffectRenderer.colors(for: EffectSettings(mode: .music), layout: layout, time: 0, audio: .silent)!
        #expect(colors.allSatisfy { max($0.r, $0.g, $0.b) <= 0.05 })
    }

    @Test func musicFadesOutSmoothlyAtTheEndOfTheHistory() {
        let l = LEDLayout(top: 40, right: 80, bottom: 40, left: 80)
        let loud = AudioLevels.Bands(bass: 1, mid: 0, treble: 0)
        let audio = AudioLevels(history: Array(repeating: loud, count: 200), historyInterval: 0.01)
        let colors = EffectRenderer.colors(for: EffectSettings(mode: .music), layout: l, time: 0, audio: audio)!
        let left = zip(l.slots(), colors).filter { $0.0.edge == .left }.sorted { $0.0.position > $1.0.position }
        let brightness = left.map { max($0.1.r, $0.1.g, $0.1.b) }
        for (a, b) in zip(brightness, brightness.dropFirst()) {
            #expect(abs(a - b) < 0.05)
        }
        #expect(brightness.last! <= 0.03 + 1e-9)
    }

    @Test func musicScrollKeepsItsBrightnessUntilTheTail() {
        #expect(abs(MusicEffect.scrollFade(age: 1, horizon: 2) - exp(-0.5)) < 1e-3)
        #expect(MusicEffect.scrollFade(age: 2, horizon: 2) == 0)
    }
}
