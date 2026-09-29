import Foundation

enum WaveEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let rate = context.rate(slowest: 0.05, fastest: 0.5)
        let n = context.count
        return (0..<n).map { i in
            let u = Double(i) / Double(max(n, 1))
            return context.color.scaled(0.3 + 0.7 * (0.5 + 0.5 * cos(2 * .pi * (2 * u - rate * context.time))))
        }
    }
}
