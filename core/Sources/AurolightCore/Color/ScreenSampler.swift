import Foundation

public struct ScreenSampler: Sendable {
    public init() {}

    static let bins = 24
    static let neutralBin = bins
    static let edgeDepth = 0.10
    static let depthScale = 0.12
    static let litRange = (0.004, 0.03)
    static let chromaRange = (0.02, 0.06)
    static let coverageRange = (0.08, 0.25)
    static let switchMargin = 1.2
    static let switchFrames = 2
    static let scoreSmoothing = 0.35
    static let presentShare = 0.05
    static let holdShare = 0.25
    static let specksRange = (0.005, 0.02)
    static let protectionRange = (0.3, 0.7)
    static let histogramBuckets = 32
    static let minReach = 0.02
    static let edgeTextWeight = 0.1
    static let liftTextWeight = 0.2
    static let liftGateRange = (0.08, 0.25)
    static let liftExponent = 0.35
    static let liftGain = 1.5

    private var key: FootprintKey?
    private var footprints: [[Tap]] = []
    private var scores: [[Double]] = []
    private var incumbent: [Int?] = []
    private var challenger: [(bin: Int, frames: Int)?] = []
    private var grid = Grid()
    private var scratch = Scratch()
    private var overlays = OverlayTracker()
    var tracksOverlays = true

    public mutating func reset() {
        for i in scores.indices { scores[i] = [Double](repeating: 0, count: Self.bins) }
        incumbent = incumbent.map { _ in nil }
        challenger = challenger.map { _ in nil }
    }

    public mutating func sample(
        bgra base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int,
        layout: LEDLayout, immersion: Double
    ) -> [RGB] {
        grid.load(bgra: base, width: width, height: height, bytesPerRow: bytesPerRow)
        if tracksOverlays { overlays.apply(to: &grid, area: layout.detectionArea) }
        let immersion = min(max(immersion, 0), 1)
        let newKey = FootprintKey(
            layout: layout, immersion: (immersion * 20).rounded() / 20,
            columns: grid.columns, rows: grid.rows)
        if newKey != key {
            key = newKey
            footprints = Self.footprints(for: layout, immersion: newKey.immersion, grid: grid)
            scores = footprints.map { _ in [Double](repeating: 0, count: Self.bins) }
            incumbent = footprints.map { _ in nil }
            challenger = footprints.map { _ in nil }
        }
        var colors: [RGB] = []
        colors.reserveCapacity(footprints.count)
        for led in footprints.indices { colors.append(color(led: led, immersion: immersion)) }
        return colors
    }

    private struct Survey {
        var protection: Double
        var edgeMedian: Double
        var footprintMedian: Double
        var brightest: Double
    }

    private mutating func survey(led: Int) -> Survey {
        scratch.clear()
        var edgeChroma = 0.0, edgeCells = 0.0
        for tap in footprints[led] {
            let c = grid.cells[tap.cell]
            let bucket = c.peakBucket
            scratch.peakHistogram[bucket] += 1
            if tap.reach > Self.minReach { scratch.reachHistogram[bucket] += 1 }
            if tap.isEdge {
                edgeChroma += c.confidence; edgeCells += 1
                scratch.edgeHistogram[bucket] += 1
            }
        }
        return Survey(
            protection: edgeCells > 0
                ? smoothstep(Self.protectionRange.0, Self.protectionRange.1, edgeChroma / edgeCells) : 0,
            edgeMedian: Self.percentile(scratch.edgeHistogram, 0.5),
            footprintMedian: Self.percentile(scratch.peakHistogram, 0.5),
            brightest: Self.percentile(scratch.reachHistogram, 0.95))
    }

    private mutating func color(led: Int, immersion: Double) -> RGB {
        let survey = survey(led: led)
        let protection = survey.protection
        var edgeSum = (r: 0.0, g: 0.0, b: 0.0), edgeCount = 0.0
        var donorSum = (r: 0.0, g: 0.0, b: 0.0), donorWeight = 0.0
        var litWeight = 0.0, colorWeight = 0.0, footprintWeight = 0.0
        var energy = 0.0, spatialSum = 0.0

        for tap in footprints[led] {
            let c = grid.cells[tap.cell]
            if tap.isEdge {
                let w = Self.isNeutralOutlier(c, typical: survey.edgeMedian) ? Self.edgeTextWeight : 1
                edgeSum.r += c.lr * w; edgeSum.g += c.lg * w; edgeSum.b += c.lb * w; edgeCount += w
            }
            // Strongest channel, not luminance, so pure blue lights the strip as well as pure green.
            let textWeight = Self.isNeutralOutlier(c, typical: survey.footprintMedian) ? Self.liftTextWeight : 1
            let bright = tap.reach * c.linearPeak * c.linearPeak * textWeight * (0.1 + 0.9 * c.confidence)
            donorSum.r += c.lr * bright; donorSum.g += c.lg * bright; donorSum.b += c.lb * bright
            donorWeight += bright
            let (lit, hue) = Self.hueWeight(tap, c, protection: protection)
            litWeight += lit
            footprintWeight += tap.weight
            if c.bin != Self.neutralBin {
                scratch.binWeight[c.bin] += hue
                scratch.binArea[c.bin] += tap.weight * c.confidence
                colorWeight += lit * c.confidence
            }
            energy += tap.reach * c.peak * textWeight
            spatialSum += tap.reach * textWeight
        }
        let edge =
            edgeCount > 0
            ? Self.encode(r: edgeSum.r / edgeCount, g: edgeSum.g / edgeCount, b: edgeSum.b / edgeCount) : .black
        let edgeValue = max(edge.r, edge.g, edge.b)

        let gate = smoothstep(Self.liftGateRange.0, Self.liftGateRange.1, survey.brightest)
        let donor =
            spatialSum > 0 ? min(pow(energy / spatialSum, Self.liftExponent) * Self.liftGain, 1) * gate : 0
        let fill = immersion * pow(1 - edgeValue, 2)
        let value = edgeValue + max(donor - edgeValue, 0) * fill

        let winner = pickHue(led: led)
        let coverage = litWeight > 1e-9 ? colorWeight / litWeight : 0
        var share = winner == nil ? 0 : smoothstep(Self.coverageRange.0, Self.coverageRange.1, coverage)
        if let winner, footprintWeight > 1e-9 {
            let n = Self.bins
            let area =
                scratch.binArea[(winner + n - 1) % n] + scratch.binArea[winner] + scratch.binArea[(winner + 1) % n]
            share *= smoothstep(Self.specksRange.0, Self.specksRange.1, area / footprintWeight)
        }

        let edgeTint = Self.normalized(edge)
        let liftColor =
            donorWeight > 1e-12
            ? Self.normalized(
                Self.encode(r: donorSum.r / donorWeight, g: donorSum.g / donorWeight, b: donorSum.b / donorWeight))
            : edgeTint
        let donorColor = RGB.mix(liftColor, edgeTint, protection)
        let lift = value - edgeValue
        let base = RGB(
            r: edgeTint.r * edgeValue + donorColor.r * lift,
            g: edgeTint.g * edgeValue + donorColor.g * lift,
            b: edgeTint.b * edgeValue + donorColor.b * lift)
        guard share > 0, let winner,
            let dominant = representative(led: led, around: winner, protection: protection)
        else {
            return Self.scaled(base, to: value)
        }
        let mixed = RGB.mix(Self.normalized(base), Self.normalized(dominant), share)
        return Self.scaled(mixed, to: value)
    }

    private mutating func pickHue(led: Int) -> Int? {
        let n = Self.bins
        let k = Self.scoreSmoothing
        var present = 0.0
        let w = scratch.binWeight
        for b in 0..<n {
            scratch.window[b] = w[(b + n - 1) % n] + w[b] + w[(b + 1) % n]
            scores[led][b] += (scratch.window[b] - scores[led][b]) * k
            present = max(present, scratch.window[b])
        }
        // Only hues on screen now qualify: holding a vanished hue would show black.
        guard present > 1e-9 else {
            incumbent[led] = nil
            challenger[led] = nil
            return nil
        }
        func isCandidate(_ b: Int) -> Bool { scratch.window[b] >= present * Self.presentShare }
        var best = -1
        for b in 0..<n where isCandidate(b) && (best < 0 || scores[led][b] > scores[led][best]) { best = b }
        let bestScore = scores[led][best]
        guard let current = incumbent[led], isCandidate(current), scores[led][current] > bestScore * Self.holdShare
        else {
            incumbent[led] = best
            challenger[led] = nil
            return best
        }
        if best != current, bestScore > scores[led][current] * Self.switchMargin {
            let frames = (challenger[led].flatMap { $0.bin == best ? $0.frames : nil } ?? 0) + 1
            if frames >= Self.switchFrames {
                incumbent[led] = best
                challenger[led] = nil
                return best
            }
            challenger[led] = (best, frames)
        } else {
            challenger[led] = nil
        }
        return current
    }

    static func hueBrightnessWeight(_ y: Double) -> Double { 0.75 + 0.25 * y.squareRoot() }

    static func hueWeight(_ tap: Tap, _ c: Grid.Cell, protection: Double) -> (lit: Double, hue: Double) {
        let lit = tap.weight * c.litLevel
        let inner = tap.isEdge ? 1 : 1 - protection
        return (lit, lit * c.confidence * c.hueBrightness * inner)
    }

    private func representative(led: Int, around bin: Int, protection: Double) -> RGB? {
        let n = Self.bins
        var sum = (l: 0.0, a: 0.0, b: 0.0), weight = 0.0
        for tap in footprints[led] {
            let c = grid.cells[tap.cell]
            guard c.bin != Self.neutralBin else { continue }
            let d = abs(c.bin - bin), distance = min(d, n - d)
            guard distance <= 1 else { continue }
            let w = Self.hueWeight(tap, c, protection: protection).hue
            sum.l += c.okL * w; sum.a += c.okA * w; sum.b += c.okB * w; weight += w
        }
        guard weight > 1e-12 else { return nil }
        let (r, g, b) = Oklab.toLinear(lightness: sum.l / weight, a: sum.a / weight, b: sum.b / weight)
        return Self.encode(r: r, g: g, b: b)
    }

    struct Tap: Sendable {
        let cell: Int
        let weight: Double
        let reach: Double
        let isEdge: Bool
    }

    struct FootprintKey: Equatable, Sendable {
        let layout: LEDLayout
        let immersion: Double
        let columns: Int, rows: Int
    }

    static func footprints(for layout: LEDLayout, immersion: Double, grid: Grid) -> [[Tap]] {
        let area = layout.detectionArea
        let counts: [ScreenEdge: Int] = [
            .top: layout.top, .right: layout.right, .bottom: layout.bottom, .left: layout.left,
        ]
        let maxDepth = edgeDepth + 0.4 * immersion
        let reachDepth = immersion > 0 ? 0.5 : edgeDepth
        return layout.slots().map { slot in
            let cellSpan =
                slot.edge == .top || slot.edge == .bottom
                ? 1 / Double(grid.columns) / area.width : 1 / Double(grid.rows) / area.height
            let pitch = max(1 / Double(max(counts[slot.edge] ?? 1, 1)), cellSpan)
            var taps: [Tap] = []
            for row in 0..<grid.rows {
                let ny = (Double(row) + 0.5) / Double(grid.rows)
                for column in 0..<grid.columns {
                    let nx = (Double(column) + 0.5) / Double(grid.columns)
                    guard area.contains(x: nx, y: ny) else { continue }
                    let ax = (nx - area.x) / area.width, ay = (ny - area.y) / area.height
                    let (u, d): (Double, Double) =
                        switch slot.edge {
                        case .top: (ax, ay)
                        case .bottom: (ax, 1 - ay)
                        case .left: (ay, ax)
                        case .right: (ay, 1 - ax)
                        }
                    let lateral = (u - slot.position) / pitch
                    guard d <= reachDepth, abs(lateral) <= 1.5 else { continue }
                    let lateralWeight = exp(-lateral * lateral / 2)
                    let nearest = min(ay, 1 - ay, ax, 1 - ax)
                    let ownership = 1 - smoothstep(0, 0.15, d - nearest)
                    taps.append(
                        Tap(
                            cell: row * grid.columns + column,
                            weight: d <= maxDepth ? lateralWeight * exp(-d / depthScale) : 0,
                            reach: lateralWeight * (1 - 0.7 * d / reachDepth) * ownership,
                            isEdge: d <= edgeDepth && abs(lateral) <= 0.5 + 1e-9))
                }
            }
            return taps
        }
    }

    static func isNeutralOutlier(_ c: Grid.Cell, typical: Double) -> Bool {
        c.confidence < 0.3 && c.peak > max(2 * typical, typical + 0.15)
    }

    static func percentile(_ histogram: [Double], _ fraction: Double) -> Double {
        let total = histogram.reduce(0, +)
        guard total > 0 else { return 0 }
        var running = 0.0
        for (i, count) in histogram.enumerated() {
            running += count
            if running >= total * fraction { return (Double(i) + 1) / Double(histogram.count) }
        }
        return 1
    }

    static func encode(r: Double, g: Double, b: Double) -> RGB {
        RGB(r: SRGB.encode(r), g: SRGB.encode(g), b: SRGB.encode(b))
    }

    static func normalized(_ c: RGB) -> RGB {
        let peak = max(c.r, c.g, c.b)
        return peak > 1e-9 ? RGB(r: c.r / peak, g: c.g / peak, b: c.b / peak) : c
    }

    static func scaled(_ c: RGB, to value: Double) -> RGB {
        let n = normalized(c)
        return RGB(r: n.r * value, g: n.g * value, b: n.b * value)
    }

    private struct Scratch {
        var binWeight = [Double](repeating: 0, count: ScreenSampler.bins)
        var binArea = [Double](repeating: 0, count: ScreenSampler.bins)
        var window = [Double](repeating: 0, count: ScreenSampler.bins)
        var peakHistogram = [Double](repeating: 0, count: ScreenSampler.histogramBuckets)
        var edgeHistogram = [Double](repeating: 0, count: ScreenSampler.histogramBuckets)
        var reachHistogram = [Double](repeating: 0, count: ScreenSampler.histogramBuckets)

        mutating func clear() {
            for i in 0..<ScreenSampler.bins {
                binWeight[i] = 0
                binArea[i] = 0
            }
            for i in 0..<ScreenSampler.histogramBuckets {
                peakHistogram[i] = 0
                edgeHistogram[i] = 0
                reachHistogram[i] = 0
            }
        }
    }
}
