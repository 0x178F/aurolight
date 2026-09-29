enum SolidEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        Array(repeating: context.color, count: context.count)
    }
}
