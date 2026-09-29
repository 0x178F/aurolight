import Foundation
import Testing

@testable import AurolightCore

/// Oklab LED error near overlays vs. the clean picture (~0.02 is just noticeable); `make benchmark`.
struct OverlayBenchmark {
    typealias Paint = @Sendable (_ u: Double, _ v: Double, _ t: Int) -> (Double, Double, Double)?

    struct Overlay: Sendable {
        let name: String
        let rect: NormRect
        var isControl = false
        let paint: Paint
    }

    static let size = (w: 480, h: 270)
    static let layout = LEDLayout(top: 48, right: 27, bottom: 48, left: 27)

    static let overlays: [Overlay] = [
        Overlay(name: "Channel logo, top right (white)", rect: NormRect(x: 0.86, y: 0.05, width: 0.09, height: 0.08)) {
            u, v, _ in
            (u > 0.86 && u < 0.95 && v > 0.05 && v < 0.13 && !Int(u * 200).isMultiple(of: 3)) ? (0.95, 0.95, 0.95) : nil
        },
        Overlay(name: "Health bar, bottom left (red)", rect: NormRect(x: 0.03, y: 0.9, width: 0.22, height: 0.05)) {
            u, v, _ in
            guard u > 0.03, u < 0.25, v > 0.9, v < 0.95 else { return nil }
            let digits = u > 0.04 && u < 0.09 && v > 0.91 && v < 0.94 && Int(u * 300).isMultiple(of: 3)
            return digits ? (1, 1, 1) : (0.9, 0.08, 0.08)
        },
        Overlay(name: "Minimap, top left (green)", rect: NormRect(x: 0.02, y: 0.03, width: 0.15, height: 0.22)) {
            u, v, _ in
            guard u > 0.02, u < 0.17, v > 0.03, v < 0.25 else { return nil }
            let road = Int(u * 90).isMultiple(of: 7) || Int(v * 70).isMultiple(of: 6)
            return road ? (0.8, 0.8, 0.7) : (0.12, 0.35, 0.15)
        },
        Overlay(name: "Scoreboard, top center (blue)", rect: NormRect(x: 0.38, y: 0.02, width: 0.24, height: 0.08)) {
            u, v, _ in
            guard u > 0.38, u < 0.62, v > 0.02, v < 0.1 else { return nil }
            let text = v > 0.04 && v < 0.08 && (u < 0.46 || u > 0.54) && Int(u * 250).isMultiple(of: 3)
            return text ? (0.95, 0.95, 0.95) : (0.1, 0.2, 0.6)
        },
        Overlay(
            name: "Control: lit sign by a moving crowd", rect: NormRect(x: 0.82, y: 0.04, width: 0.1, height: 0.1),
            isControl: true
        ) { u, v, t in
            if u > 0.82, u < 0.92, v > 0.04, v < 0.14 { return (0.95, 0.3, 0.6) }
            if v > 0.5, v < 0.9 {
                let w = sin(u * 90 + v * 40 + Double(t) * 0.7) * sin(u * 37 - Double(t) * 0.5)
                return (0.3 + 0.25 * w, 0.3 + 0.2 * w, 0.35 + 0.15 * w)
            }
            return v < 0.5 ? (0.05, 0.05, 0.12) : (0.1, 0.1, 0.1)
        },
        Overlay(
            name: "Control: buoy surrounded by moving water",
            rect: NormRect(x: 0.45, y: 0.84, width: 0.07, height: 0.07),
            isControl: true
        ) { u, v, t in
            if u > 0.45, u < 0.52, v > 0.84, v < 0.91 { return (0.95, 0.45, 0.1) }
            if v > 0.55 {
                let w = sin(u * 80 + v * 50 + Double(t) * 1.7) * sin(v * 30 - Double(t) * 1.3)
                return (0.15 + 0.12 * w, 0.35 + 0.25 * w, 0.5 + 0.3 * w)
            }
            return (0.5, 0.65, 0.85)
        },
        Overlay(
            name: "Control: overcast sky in a tracking shot",
            rect: NormRect(x: 0.55, y: 0, width: 0.2, height: 0.15),
            isControl: true
        ) { u, v, _ in
            (u > 0.55 && u < 0.75 && v < 0.15) ? (0.88, 0.9, 0.92) : nil
        },
        Overlay(
            name: "Control: still sky over a moving scene", rect: NormRect(x: 0, y: 0, width: 1, height: 0.33),
            isControl: true
        ) { _, v, _ in v < 0.33 ? (0.45, 0.62, 0.85) : nil },
    ]

    static func frame(t: Int, overlay: Paint?) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: size.w * size.h * 4)
        for y in 0..<size.h {
            for x in 0..<size.w {
                let u = Double(x) / Double(size.w), v = Double(y) / Double(size.h)
                let tt = Double(t) / 15
                var c = (
                    0.55 + 0.35 * sin(u * 3 + tt), 0.3 + 0.25 * sin(v * 4 - tt * 0.8),
                    0.35 + 0.3 * sin((u + v) * 2 + tt)
                )
                if let o = overlay?(u, v, t) { c = o }
                let o = (y * size.w + x) * 4
                px[o] = UInt8(max(0, min(1, c.2)) * 255)
                px[o + 1] = UInt8(max(0, min(1, c.1)) * 255)
                px[o + 2] = UInt8(max(0, min(1, c.0)) * 255)
            }
        }
        return px
    }

    static func oklab(_ c: RGB) -> (Double, Double, Double) {
        Oklab.fromLinear(r: SRGB.decode(c.r), g: SRGB.decode(c.g), b: SRGB.decode(c.b))
    }

    static func measure(_ overlay: Overlay) -> (off: (mean: Double, p95: Double), on: (mean: Double, p95: Double)) {
        var reference = ScreenSampler(), without = ScreenSampler(), with = ScreenSampler()
        reference.tracksOverlays = false
        without.tracksOverlays = false
        let slots = layout.slots()
        let near = slots.indices.filter { i in
            let s = slots[i], r = overlay.rect
            switch s.edge {
            case .top: return r.y < 0.3 && s.position > r.x - 0.05 && s.position < r.x + r.width + 0.05
            case .bottom: return r.y + r.height > 0.7 && s.position > r.x - 0.05 && s.position < r.x + r.width + 0.05
            case .left: return r.x < 0.3 && s.position > r.y - 0.05 && s.position < r.y + r.height + 0.05
            case .right: return r.x + r.width > 0.7 && s.position > r.y - 0.05 && s.position < r.y + r.height + 0.05
            }
        }
        var errors = (off: [Double](), on: [Double]())
        for t in 0..<300 {
            let clean = frame(t: t, overlay: overlay.isControl ? overlay.paint : nil)
            let dirty = frame(t: t, overlay: overlay.paint)
            func sample(_ sampler: inout ScreenSampler, _ pixels: [UInt8]) -> [RGB] {
                pixels.withUnsafeBytes {
                    sampler.sample(
                        bgra: $0.baseAddress!, width: size.w, height: size.h, bytesPerRow: size.w * 4, layout: layout,
                        immersion: 0.4)
                }
            }
            let a = sample(&reference, clean), b = sample(&without, dirty), c = sample(&with, dirty)
            guard t >= 180 else { continue }
            for i in near {
                errors.off.append(distance(a[i], b[i]))
                errors.on.append(distance(a[i], c[i]))
            }
        }
        func summary(_ e: [Double]) -> (mean: Double, p95: Double) {
            let sorted = e.sorted()
            return (e.reduce(0, +) / Double(max(e.count, 1)), sorted.isEmpty ? 0 : sorted[sorted.count * 95 / 100])
        }
        return (summary(errors.off), summary(errors.on))
    }

    static func distance(_ a: RGB, _ b: RGB) -> Double {
        let p = oklab(a), q = oklab(b)
        return ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) + (p.2 - q.2) * (p.2 - q.2)).squareRoot()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUROLIGHT_BENCHMARK"] != nil))
    func report() {
        let rule = String(repeating: "-", count: 88)
        var lines = ["", "Overlay benchmark: LED color error near the overlay (Oklab, immersion 0.4)", rule]
        lines.append("Overlay".padding(toLength: 44, withPad: " ", startingAt: 0) + "without tracking   with tracking")
        lines.append("".padding(toLength: 44, withPad: " ", startingAt: 0) + "mean   p95         mean   p95")
        for overlay in Self.overlays {
            let r = Self.measure(overlay)
            lines.append(
                overlay.name.padding(toLength: 44, withPad: " ", startingAt: 0)
                    + String(format: "%.3f  %.3f       %.3f  %.3f", r.off.mean, r.off.p95, r.on.mean, r.on.p95))
            if overlay.isControl {
                #expect(r.on.p95 < 0.01, "\(overlay.name): tracking changed still picture (\(r.on.p95))")
            } else {
                #expect(
                    r.on.mean <= 0.3 * r.off.mean, "\(overlay.name): error only down to \(r.on.mean) from \(r.off.mean)"
                )
            }
        }
        lines.append(rule)
        print(lines.joined(separator: "\n"))
    }
}
