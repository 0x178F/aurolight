import Foundation

enum OceanEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let n = context.count
        let theta = 2 * .pi * context.rate(slowest: 0.05, fastest: 0.3) * context.time
        let deep = RGB(r: 0, g: 0.1, b: 0.45), teal = RGB(r: 0, g: 0.55, b: 0.6), foam = RGB(r: 0.6, g: 0.85, b: 1)
        return (0..<n).map { i in
            let u = 2 * .pi * Double(i) / Double(max(n, 1))
            let a = min(max(0.5 + 0.3 * sin(3 * u - theta) + 0.2 * sin(5 * u + 1.3 * theta), 0), 1)
            let water = RGB.mix(deep, teal, a)
            return a > 0.85 ? RGB.mix(water, foam, (a - 0.85) / 0.15 * 0.6) : water
        }
    }
}
