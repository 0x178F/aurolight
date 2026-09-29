import Foundation

enum BreathingEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let breathsPerSecond = context.rate(slowest: 0.05, fastest: 0.5)
        let phase = (1 - cos(2 * .pi * breathsPerSecond * context.time)) / 2
        return Array(repeating: context.color.scaled(0.12 + 0.88 * phase), count: context.count)
    }
}
