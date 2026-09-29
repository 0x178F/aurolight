enum ColorCycleEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let cyclesPerSecond = context.rate(slowest: 0.005, fastest: 0.1)
        return Array(repeating: RGB(hue: cyclesPerSecond * context.time, saturation: 1, value: 1), count: context.count)
    }
}
