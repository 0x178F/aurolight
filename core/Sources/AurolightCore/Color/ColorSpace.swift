import Foundation

enum SRGB {
    static let decodeTable: [Double] = (0...255).map { decode(Double($0) / 255) }

    static func decode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func encode(_ v: Double) -> Double {
        let c = min(max(v, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

/// Oklab (Björn Ottosson), from/to linear sRGB.
enum Oklab {
    static func fromLinear(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    static func toLinear(lightness: Double, a: Double, b: Double) -> (Double, Double, Double) {
        let (r, g, b) = unclampedLinear(lightness: lightness, a: a, b: b)
        return (max(r, 0), max(g, 0), max(b, 0))
    }

    private static func unclampedLinear(lightness: Double, a: Double, b: Double) -> (Double, Double, Double) {
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    /// Scales an sRGB-encoded color's chroma at fixed lightness and hue. A boost is reduced as far as needed to
    /// stay inside sRGB, so it never clips into a different hue.
    static func saturate(_ color: RGB, by factor: Double) -> RGB {
        let (lightness, a, b) = fromLinear(r: SRGB.decode(color.r), g: SRGB.decode(color.g), b: SRGB.decode(color.b))
        func scaled(_ k: Double) -> (Double, Double, Double) {
            unclampedLinear(lightness: lightness, a: a * k, b: b * k)
        }
        func fits(_ c: (Double, Double, Double)) -> Bool {
            min(c.0, c.1, c.2) >= -1e-6 && max(c.0, c.1, c.2) <= 1 + 1e-6
        }
        var k = factor
        if factor > 1, !fits(scaled(factor)) {
            var low = 1.0, high = factor
            for _ in 0..<16 {
                let mid = (low + high) / 2
                if fits(scaled(mid)) { low = mid } else { high = mid }
            }
            k = low
        }
        let c = scaled(k)
        return RGB(r: SRGB.encode(c.0), g: SRGB.encode(c.1), b: SRGB.encode(c.2))
    }
}
