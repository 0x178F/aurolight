import Foundation

/// Corrects the strip's white point: LEDs at full power usually look bluer than a screen's white.
public struct WhiteBalance: Codable, Equatable, Sendable {
    public static let neutralTemperature = 6500.0
    public static let temperatureRange = 3000.0...10000.0
    public static let neutral = WhiteBalance()

    public var temperature: Double
    /// -1 (greener) ... 1 (more magenta).
    public var tint: Double

    public init(temperature: Double = neutralTemperature, tint: Double = 0) {
        self.temperature = temperature
        self.tint = tint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temperature = c.decode(.temperature, default: Self.neutralTemperature)
        tint = c.decode(.tint, default: 0)
    }

    /// Linear-light gains relative to 6500 K; the largest is 1, so balancing never brightens a channel.
    public var gains: RGB {
        let kelvin = min(max(temperature, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound)
        let target = Self.linearBlackbody(kelvin), reference = Self.linearBlackbody(Self.neutralTemperature)
        var r = target.r / reference.r, g = target.g / reference.g, b = target.b / reference.b
        let tint = min(max(tint, -1), 1)
        if tint > 0 {
            g *= 1 - Self.tintStrength * tint
        } else {
            r *= 1 + Self.tintStrength * tint
            b *= 1 + Self.tintStrength * tint
        }
        let peak = max(r, g, b)
        return RGB(r: r / peak, g: g / peak, b: b / peak)
    }

    private static let tintStrength = 0.25

    // Tanner Helland's fit of a blackbody's sRGB color, decoded to linear light.
    private static func linearBlackbody(_ kelvin: Double) -> RGB {
        let t = kelvin / 100
        let red = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307
        func linear(_ v: Double) -> Double { SRGB.decode(min(max(v, 1), 255) / 255) }
        return RGB(r: linear(red), g: linear(green), b: linear(blue))
    }
}
