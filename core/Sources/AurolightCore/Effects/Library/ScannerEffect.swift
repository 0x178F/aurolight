import Foundation

enum ScannerEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let sweepsPerSecond = context.rate(slowest: 0.05, fastest: 0.4)
        let position = 0.5 - 0.5 * cos(2 * .pi * sweepsPerSecond * context.time)
        return context.layout.slots().map { slot in
            let (x, _) = screenPoint(slot)
            return context.color.scaled(0.04 + 0.96 * exp(-pow((x - position) / 0.05, 2)))
        }
    }
}
