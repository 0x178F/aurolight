import Foundation

public struct ColorProcessor: Sendable {
    public var settings: ColorSettings
    /// Per-channel gains from `WhiteBalance`, applied last in linear light.
    public var gains = RGB(r: 1, g: 1, b: 1)
    public private(set) var smoothed: [RGB] = []

    public init(settings: ColorSettings = ColorSettings()) {
        self.settings = settings
    }

    public mutating func process(_ input: [RGB], smooth: Bool = true) -> [UInt8] {
        var s = settings
        s.brightness = min(max(s.brightness, 0), 1)
        s.smoothing = min(max(s.smoothing, 0), 0.95)
        s.saturation = max(s.saturation, 0)
        s.gamma = max(s.gamma, 0.1)  // pow(0, 0) = 1 would turn black white
        s.blackLevel = min(max(s.blackLevel, 0), 1)

        if !smooth || smoothed.count != input.count {
            smoothed = input
        } else {
            let k = 1 - s.smoothing
            for i in input.indices {
                smoothed[i].r += (input[i].r - smoothed[i].r) * k
                smoothed[i].g += (input[i].g - smoothed[i].g) * k
                smoothed[i].b += (input[i].b - smoothed[i].b) * k
            }
        }

        var out = [UInt8]()
        out.reserveCapacity(smoothed.count * 3)
        for color in smoothed {
            let c = Self.finalize(color, s, gains: gains)
            out.append(Self.byte(c.r))
            out.append(Self.byte(c.g))
            out.append(Self.byte(c.b))
        }
        return out
    }

    static func finalize(_ c: RGB, _ settings: ColorSettings, gains: RGB = RGB(r: 1, g: 1, b: 1)) -> RGB {
        let clamped = c.clamped
        let saturated = settings.saturation == 1 ? clamped : Oklab.saturate(clamped, by: settings.saturation)
        guard max(saturated.r, saturated.g, saturated.b) >= settings.blackLevel else { return .black }

        let gamma = settings.gamma
        let brightness = settings.brightness
        return RGB(
            r: pow(saturated.r, gamma) * brightness * gains.r,
            g: pow(saturated.g, gamma) * brightness * gains.g,
            b: pow(saturated.b, gamma) * brightness * gains.b
        )
    }

    public static func byte(_ v: Double) -> UInt8 {
        guard v.isFinite else { return v > 0 ? 255 : 0 }
        return UInt8((min(max(v, 0), 1) * 255).rounded())
    }
}
