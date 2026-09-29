enum RainbowEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let turnsPerSecond = context.rate(slowest: 0.02, fastest: 0.5)
        let n = context.count
        return (0..<n).map { i in
            RGB(hue: Double(i) / Double(max(n, 1)) + turnsPerSecond * context.time, saturation: 1, value: 1)
        }
    }
}
