public enum ColorPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case natural, vivid, cinema, custom

    public var id: Self { self }

    public struct Tuning: Codable, Equatable, Sendable {
        public var smoothing: Double
        public var saturation: Double
        public var gamma: Double
        public var blackLevel: Double

        public init(smoothing: Double, saturation: Double, gamma: Double, blackLevel: Double) {
            self.smoothing = smoothing
            self.saturation = saturation
            self.gamma = gamma
            self.blackLevel = blackLevel
        }

        public init(_ color: ColorSettings) {
            self.init(
                smoothing: color.smoothing, saturation: color.saturation, gamma: color.gamma,
                blackLevel: color.blackLevel)
        }

        func applied(to color: ColorSettings) -> ColorSettings {
            var c = color
            (c.smoothing, c.saturation, c.gamma, c.blackLevel) = (smoothing, saturation, gamma, blackLevel)
            return c
        }
    }

    var values: (tuning: Tuning, immersion: Double)? {
        switch self {
        // Gamma 2.2 turns the screen's sRGB into the linear light LEDs emit; Natural matches the screen.
        case .natural: (Tuning(smoothing: 0.6, saturation: 1.0, gamma: 2.2, blackLevel: 0.03), 0.4)
        case .vivid: (Tuning(smoothing: 0.45, saturation: 1.35, gamma: 2.2, blackLevel: 0.04), 0.6)
        case .cinema: (Tuning(smoothing: 0.7, saturation: 1.1, gamma: 2.4, blackLevel: 0.05), 0.8)
        case .custom: nil
        }
    }

    static func matching(_ color: ColorSettings) -> ColorPreset {
        allCases.first { $0.values?.tuning == Tuning(color) } ?? .custom
    }
}

extension ColorSettings {
    public mutating func select(_ preset: ColorPreset) {
        guard preset != self.preset else { return }
        if self.preset == .custom { customTuning = ColorPreset.Tuning(self) }
        self.preset = preset
        if let values = preset.values {
            self = values.tuning.applied(to: self)
            immersion = values.immersion
        } else if let customTuning {
            self = customTuning.applied(to: self)
        }
    }
}
