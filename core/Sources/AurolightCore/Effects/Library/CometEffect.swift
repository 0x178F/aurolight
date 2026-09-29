import Foundation

enum CometEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let n = context.count
        let lapsPerSecond = context.rate(slowest: 0.05, fastest: 0.8)
        let head = fract(lapsPerSecond * context.time)
        return (0..<n).map { i in
            let behind = fract(head - Double(i) / Double(max(n, 1)))
            return context.color.scaled(0.03 + 0.97 * pow(max(0, 1 - behind / 0.15), 2))
        }
    }
}
