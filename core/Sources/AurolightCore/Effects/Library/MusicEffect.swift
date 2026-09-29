import Foundation

enum MusicEffect {
    static let scrollLEDsPerSecond = 40.0

    static func colors(in context: EffectContext) -> [RGB] {
        let audio = context.audio, layout = context.layout
        let horizon = Double(audio.history.count) * audio.historyInterval
        return layout.slots().map { slot in
            let cell = mirroredPathIndex(slot, layout: layout)
            var color = RGB.black
            var weightSum = 0.0
            for tap in -2...2 {
                let weight = exp(-Double(tap * tap) / 8)
                let age = max(cell + Double(tap) + 0.5, 0) / scrollLEDsPerSecond
                let fade = scrollFade(age: age, horizon: horizon)
                let c = bandColor(audio.bands(atAge: age)).scaled(fade)
                color = RGB(r: color.r + c.r * weight, g: color.g + c.g * weight, b: color.b + c.b * weight)
                weightSum += weight
            }
            let scroll = color.scaled(1 / weightSum)
            return RGB(r: 0.03 + 0.97 * scroll.r, g: 0.03 + 0.97 * scroll.g, b: 0.03 + 0.97 * scroll.b)
        }
    }

    static func scrollFade(age: Double, horizon: Double) -> Double {
        guard horizon > 0 else { return 0 }
        return exp(-age / 2) * (1 - smoothstep(0.8 * horizon, horizon, age))
    }

    private static func bandColor(_ b: AudioLevels.Bands) -> RGB {
        let r = b.bass * 1 + b.mid * 0.04 + b.treble * 0.25
        let g = b.bass * 0.25 + b.mid * 0.8 + b.treble * 0.15
        let bl = b.bass * 0.04 + b.mid * 0.45 + b.treble * 1
        let peak = max(r, g, bl)
        guard peak > 1e-6 else { return .black }
        let level = min(max(b.bass, b.mid, b.treble), 1)
        return RGB(r: r / peak * level, g: g / peak * level, b: bl / peak * level)
    }

    private static func mirroredPathIndex(_ slot: LEDSlot, layout: LEDLayout) -> Double {
        let bottom = Double(max(layout.bottom, 0)), top = Double(max(layout.top, 0))
        let isLeft = slot.edge == .left || ((slot.edge == .top || slot.edge == .bottom) && slot.position < 0.5)
        let side = Double(max(isLeft ? layout.left : layout.right, 0))
        switch slot.edge {
        case .bottom: return abs(slot.position - 0.5) * bottom
        case .left, .right: return bottom / 2 + (1 - slot.position) * side
        case .top: return bottom / 2 + side + (0.5 - abs(slot.position - 0.5)) * top
        }
    }
}
