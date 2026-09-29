import Foundation

enum AuroraEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let n = context.count
        let theta = 2 * .pi * context.rate(slowest: 0.02, fastest: 0.2) * context.time
        let teal = RGB(r: 0.05, g: 0.9, b: 0.6), violet = RGB(r: 0.55, g: 0.15, b: 1)
        return (0..<n).map { i in
            let u = 2 * .pi * Double(i) / Double(max(n, 1))
            let a = min(max(0.5 + 0.3 * sin(u - theta) + 0.2 * sin(2 * u + 0.7 * theta), 0), 1)
            return RGB.mix(teal, violet, a).scaled(0.7 + 0.3 * sin(3 * u - 1.3 * theta))
        }
    }
}
