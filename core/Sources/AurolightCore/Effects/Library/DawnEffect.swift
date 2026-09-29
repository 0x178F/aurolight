enum DawnEffect {
    static func sunrise(in context: EffectContext) -> [RGB] {
        Array(repeating: ramp(context.fadeProgress), count: context.count)
    }

    static func sunset(in context: EffectContext) -> [RGB] {
        Array(repeating: ramp(1 - context.fadeProgress), count: context.count)
    }

    private static func ramp(_ progress: Double) -> RGB {
        let p = min(max(progress, 0), 1)
        let deepRed = RGB(r: 0.6, g: 0.05, b: 0), orange = RGB(r: 1, g: 0.4, b: 0.05),
            warmWhite = RGB(r: 1, g: 0.8, b: 0.55)
        if p < 0.4 { return RGB.mix(.black, deepRed, p / 0.4) }
        if p < 0.75 { return RGB.mix(deepRed, orange, (p - 0.4) / 0.35) }
        return RGB.mix(orange, warmWhite, (p - 0.75) / 0.25)
    }
}
