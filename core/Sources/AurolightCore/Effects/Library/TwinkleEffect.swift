import Foundation

enum TwinkleEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let rate = context.rate(slowest: 0.1, fastest: 1)
        return (0..<context.count).map { i in
            let z = rate * context.time + pseudoRandom(i, -1)
            let slot = z.rounded(.down)
            let q = z - slot
            let flash = pseudoRandom(i, Int(slot)) > 0.88 ? pow(sin(.pi * q), 2) : 0
            return context.color.scaled(0.25 + 0.75 * flash)
        }
    }
}
