public struct RGB: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let black = RGB(r: 0, g: 0, b: 0)

    /// Rec. 709 luma of encoded components, not linear luminance.
    public var luma: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    public var clamped: RGB {
        RGB(r: min(max(r, 0), 1), g: min(max(g, 0), 1), b: min(max(b, 0), 1))
    }

    public init(hue: Double, saturation: Double, value: Double) {
        let hue = hue.isFinite ? hue : 0
        let h = (hue - hue.rounded(.down)) * 6
        let i = Int(h) % 6
        let f = h - Double(Int(h))
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * f)
        let t = value * (1 - saturation * (1 - f))
        switch i {
        case 0: self.init(r: value, g: t, b: p)
        case 1: self.init(r: q, g: value, b: p)
        case 2: self.init(r: p, g: value, b: t)
        case 3: self.init(r: p, g: q, b: value)
        case 4: self.init(r: t, g: p, b: value)
        default: self.init(r: value, g: p, b: q)
        }
    }

    /// Hue in 0..<1; 0 for grays.
    public var hue: Double {
        let high = max(r, g, b), delta = high - min(r, g, b)
        guard delta > 0 else { return 0 }
        let sector =
            high == r
            ? (g - b) / delta
            : high == g
                ? (b - r) / delta + 2
                : (r - g) / delta + 4
        let h = sector / 6
        return h < 0 ? h + 1 : h
    }

    public var saturation: Double {
        let high = max(r, g, b)
        return high > 0 ? (high - min(r, g, b)) / high : 0
    }

    public func scaled(_ factor: Double) -> RGB {
        RGB(r: r * factor, g: g * factor, b: b * factor)
    }
}

extension RGB {
    public static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }
}
