import Foundation

enum FireEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let rate = context.rate(slowest: 0.8, fastest: 3.2)
        let time = context.time
        return context.layout.slots().map { slot in
            let (x, y) = screenPoint(slot)
            let flicker = 0.6 * valueNoise(x * 6, time * rate) + 0.4 * valueNoise(x * 14 + 3, time * rate * 2.3)
            return ramp(pow(y, 1.4) * (0.35 + 0.9 * flicker))
        }
    }

    private static func ramp(_ heat: Double) -> RGB {
        let h = min(max(heat, 0), 1)
        if h < 0.35 { return RGB(r: h / 0.35, g: 0, b: 0) }
        if h < 0.7 { return RGB(r: 1, g: (h - 0.35) / 0.35 * 0.55, b: 0) }
        let t = (h - 0.7) / 0.3
        return RGB(r: 1, g: 0.55 + 0.35 * t, b: 0.35 * t)
    }
}
