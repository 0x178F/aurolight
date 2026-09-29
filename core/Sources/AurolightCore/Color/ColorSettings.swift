public struct ColorSettings: Codable, Equatable, Sendable {
    public var brightness: Double
    public var smoothing: Double
    public var saturation: Double
    public var gamma: Double
    public var blackLevel: Double
    public var immersion: Double
    public internal(set) var preset: ColorPreset
    public internal(set) var customTuning: ColorPreset.Tuning?

    public init(
        brightness: Double = 0.8,
        smoothing: Double = 0.6,
        saturation: Double = 1.0,
        gamma: Double = 2.2,
        blackLevel: Double = 0.03,
        immersion: Double = 0.4
    ) {
        self.brightness = brightness
        self.smoothing = smoothing
        self.saturation = saturation
        self.gamma = gamma
        self.blackLevel = blackLevel
        self.immersion = immersion
        preset = .natural
        customTuning = nil
        preset = ColorPreset.matching(self)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ColorSettings()
        brightness = c.decode(.brightness, default: d.brightness)
        smoothing = c.decode(.smoothing, default: d.smoothing)
        saturation = c.decode(.saturation, default: d.saturation)
        gamma = c.decode(.gamma, default: d.gamma)
        blackLevel = c.decode(.blackLevel, default: d.blackLevel)
        immersion = c.decode(.immersion, default: d.immersion)
        customTuning = c.decodeLenient(.customTuning)
        preset = .natural
        preset = c.decodeLenient(.preset) ?? ColorPreset.matching(self)
        // A named preset means its current tuning, so retuned presets reach saved settings too.
        if let tuning = preset.values?.tuning { self = tuning.applied(to: self) }
    }
}
