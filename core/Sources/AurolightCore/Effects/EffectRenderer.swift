public enum EffectRenderer {
    public static func colors(
        for effect: EffectSettings, layout: LEDLayout, time: Double,
        audio: AudioLevels = .silent
    ) -> [RGB]? {
        let context = EffectContext(settings: effect, layout: layout, time: time, audio: audio)
        switch effect.mode {
        case .screen: return nil
        case .solid: return SolidEffect.colors(in: context)
        case .breathing: return BreathingEffect.colors(in: context)
        case .candle: return CandleEffect.colors(in: context)
        case .aurora: return AuroraEffect.colors(in: context)
        case .ocean: return OceanEffect.colors(in: context)
        case .lavaLamp: return LavaLampEffect.colors(in: context)
        case .horizon: return HorizonEffect.colors(in: context)
        case .wave: return WaveEffect.colors(in: context)
        case .pulse: return PulseEffect.colors(in: context)
        case .scanner: return ScannerEffect.colors(in: context)
        case .comet: return CometEffect.colors(in: context)
        case .twinkle: return TwinkleEffect.colors(in: context)
        case .fire: return FireEffect.colors(in: context)
        case .rainbow: return RainbowEffect.colors(in: context)
        case .colorCycle: return ColorCycleEffect.colors(in: context)
        case .music: return MusicEffect.colors(in: context)
        case .sunrise: return DawnEffect.sunrise(in: context)
        case .sunset: return DawnEffect.sunset(in: context)
        }
    }
}
