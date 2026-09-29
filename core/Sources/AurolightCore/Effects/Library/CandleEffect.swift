import Foundation

enum CandleEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let psi = 2 * .pi * context.rate(slowest: 0.3, fastest: 1.5) * context.time
        let base =
            0.70 + 0.12 * sin(psi) + 0.08 * sin(2.0.squareRoot() * psi + 1) + 0.05 * sin(3.0.squareRoot() * psi + 2)
        return (0..<context.count).map { i in
            context.color.scaled(base + 0.04 * sin(1.7 * psi + Double(i) * 0.9))
        }
    }
}
