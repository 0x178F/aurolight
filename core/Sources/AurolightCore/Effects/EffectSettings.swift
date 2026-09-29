public enum LightMode: String, Codable, CaseIterable, Identifiable, Sendable {
    public var id: Self { self }

    case screen
    case solid
    case breathing, candle, aurora, ocean, lavaLamp, horizon
    case wave, comet, pulse, scanner, twinkle, fire, rainbow, colorCycle
    case music
    case sunrise, sunset

    public struct Controls: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let color = Controls(rawValue: 1 << 0)
        public static let speed = Controls(rawValue: 1 << 1)
        public static let duration = Controls(rawValue: 1 << 2)
    }

    public var controls: Controls {
        switch self {
        case .screen, .music: []
        case .solid: [.color]
        case .breathing, .candle, .wave, .comet, .pulse, .scanner, .twinkle: [.color, .speed]
        case .aurora, .ocean, .lavaLamp, .horizon, .fire, .rainbow, .colorCycle: [.speed]
        case .sunrise, .sunset: [.duration]
        }
    }
}

public struct EffectSettings: Codable, Equatable, Sendable {
    public var mode: LightMode
    public var color: RGB
    public var speed: Double
    public var fadeMinutes: Double

    public init(
        mode: LightMode = .screen,
        color: RGB = RGB(r: 1, g: 0.55, b: 0.2),
        speed: Double = 0.4,
        fadeMinutes: Double = 20
    ) {
        self.mode = mode
        self.color = color
        self.speed = speed
        self.fadeMinutes = fadeMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EffectSettings()
        mode = c.decode(.mode, default: d.mode)
        color = c.decode(.color, default: d.color)
        speed = c.decode(.speed, default: d.speed)
        fadeMinutes = c.decode(.fadeMinutes, default: d.fadeMinutes)
    }
}
