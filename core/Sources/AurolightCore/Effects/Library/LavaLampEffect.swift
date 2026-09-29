import Foundation

enum LavaLampEffect {
    static func colors(in context: EffectContext) -> [RGB] {
        let n = context.count
        let rate = context.rate(slowest: 0.01, fastest: 0.08)
        let blobs = [(v: 1.0, phase: 0.0), (v: -0.7, phase: 0.35), (v: 0.45, phase: 0.7)]
        let magenta = RGB(r: 0.9, g: 0.05, b: 0.4), red = RGB(r: 1, g: 0.1, b: 0.05), orange = RGB(r: 1, g: 0.45, b: 0)
        return (0..<n).map { i in
            let u = Double(i) / Double(max(n, 1))
            let heat = min(
                blobs.reduce(0.0) { sum, blob in
                    let d = circularDistance(u, fract(blob.v * rate * context.time + blob.phase))
                    return sum + exp(-pow(d / 0.08, 2))
                }, 1)
            let hue = heat < 0.5 ? RGB.mix(magenta, red, heat * 2) : RGB.mix(red, orange, (heat - 0.5) * 2)
            return hue.scaled(0.25 + 0.75 * heat)
        }
    }
}
