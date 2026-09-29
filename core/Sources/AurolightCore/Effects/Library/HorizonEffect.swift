import Foundation

enum HorizonEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let theta = 2 * .pi * context.rate(slowest: 0.02, fastest: 0.2) * context.time
        let warm = RGB(r: 1, g: 0.5, b: 0.15), cool = RGB(r: 0.2, g: 0.45, b: 1)
        let horizon = 0.5 + 0.2 * sin(theta)
        return context.layout.slots().map { slot in
            let a = (1 + tanh((screenPoint(slot).y - horizon) / 0.25)) / 2
            return RGB.mix(cool, warm, a)
        }
    }
}
