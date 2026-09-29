import Foundation

enum PulseEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let ringsPerSecond = context.rate(slowest: 0.15, fastest: 1.2)
        let radius = fract(ringsPerSecond * context.time) * 1.3
        return context.layout.slots().map { slot in
            let (x, y) = screenPoint(slot)
            let d = hypot(x - 0.5, y - 1) / hypot(0.5, 1)
            return context.color.scaled(0.05 + 0.95 * exp(-pow((d - radius) / 0.07, 2)))
        }
    }
}
