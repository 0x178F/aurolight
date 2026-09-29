public enum EdgeReading: Equatable, Sendable {
    case bar(Double)
    case none
    case likelyBar(Double)
    case unknown
}

public struct BarReading: Equatable, Sendable {
    public var top: EdgeReading
    public var right: EdgeReading
    public var bottom: EdgeReading
    public var left: EdgeReading

    public init(top: EdgeReading, right: EdgeReading, bottom: EdgeReading, left: EdgeReading) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public static let unknown = BarReading(top: .unknown, right: .unknown, bottom: .unknown, left: .unknown)

    public subscript(edge: ScreenEdge) -> EdgeReading {
        get {
            switch edge {
            case .top: top
            case .right: right
            case .bottom: bottom
            case .left: left
            }
        }
        set {
            switch edge {
            case .top: top = newValue
            case .right: right = newValue
            case .bottom: bottom = newValue
            case .left: left = newValue
            }
        }
    }
}

public enum BlackBarDetector {
    static let segments = 8
    static let darkSegmentsNeeded = 6
    // Above limited-range black (16).
    static let maxBlackLuma = 22.0
    static let maxBlackChannel = 30.0
    static let maxBlackPeak = 60.0
    static let maxBarVariation = 5.0
    static let abruptStep = 3.0
    static let minPictureLevel = 36.0
    static let minContrast = 12.0
    static let minPictureColor = 48.0
    static let minColorContrast = 24.0
    static let minLitShare = 0.5
    static let boundaryLines = 3
    static let maxBarFraction = 0.4
    static let rowSamples = 160
    static let columnSamples = 96
    static let subtitleGapDivisor = 12
    static let subtitleDarkSegments = 2

    public static func read(bgra base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) -> BarReading {
        guard width > 16, height > 16 else { return .unknown }
        var scanner = Scanner(
            pixels: base.assumingMemoryBound(to: UInt8.self), width: width, height: height, bytesPerRow: bytesPerRow)
        return BarReading(
            top: scanner.edge(horizontal: true, size: height) { $0 },
            right: scanner.edge(horizontal: false, size: width) { width - 1 - $0 },
            bottom: scanner.edge(horizontal: true, size: height) { height - 1 - $0 },
            left: scanner.edge(horizontal: false, size: width) { $0 }
        )
    }
}

private struct Line {
    var darkSegments: Int
    var level: Double
    var color: Double
    var trimmedMean: Double
    var litShare: Double
}

private struct Scanner {
    typealias Detector = BlackBarDetector
    let pixels: UnsafePointer<UInt8>
    let width: Int, height: Int, bytesPerRow: Int
    var peak = [Double](repeating: 0, count: Detector.segments)
    var lumaSum = [Double](repeating: 0, count: Detector.segments)
    var channelSum = [Double](repeating: 0, count: Detector.segments)
    var count = [Int](repeating: 0, count: Detector.segments)
    var sortedPeaks = [Double](repeating: 0, count: Detector.segments)
    var sortedColors = [Double](repeating: 0, count: Detector.segments)
    var sortedMeans = [Double](repeating: 0, count: Detector.segments)

    mutating func line(horizontal: Bool, index: Int) -> Line {
        let length = horizontal ? width : height
        let samples = min(length, horizontal ? Detector.rowSamples : Detector.columnSamples)
        for i in 0..<Detector.segments {
            peak[i] = 0
            lumaSum[i] = 0
            channelSum[i] = 0
            count[i] = 0
        }
        var lit = 0
        for s in 0..<samples {
            let pos = s * length / samples
            let p = horizontal ? pixels + index * bytesPerRow + pos * 4 : pixels + pos * bytesPerRow + index * 4
            let luma = 0.0722 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.2126 * Double(p[2])
            let seg = s * Detector.segments / samples
            peak[seg] = max(peak[seg], luma)
            lumaSum[seg] += luma
            let channel = Double(max(p[0], p[1], p[2]))
            channelSum[seg] += channel
            count[seg] += 1
            if luma >= Detector.minPictureLevel || channel >= Detector.minPictureColor { lit += 1 }
        }
        let dark = (0..<Detector.segments).count {
            let n = Double(max(count[$0], 1))
            return lumaSum[$0] / n <= Detector.maxBlackLuma && channelSum[$0] / n <= Detector.maxBlackChannel
                && peak[$0] <= Detector.maxBlackPeak
        }
        for i in 0..<Detector.segments { sortedPeaks[i] = peak[i] }
        sortedPeaks.sort()
        for i in 0..<Detector.segments {
            sortedColors[i] = channelSum[i] / Double(max(count[i], 1))
            sortedMeans[i] = lumaSum[i] / Double(max(count[i], 1))
        }
        sortedColors.sort()
        sortedMeans.sort()
        return Line(
            darkSegments: dark, level: sortedPeaks[Detector.segments / 2],
            color: sortedColors[Detector.segments / 2],
            trimmedMean: sortedMeans[0..<(Detector.segments - 2)].reduce(0, +) / Double(Detector.segments - 2),
            litShare: Double(lit) / Double(samples))
    }

    mutating func edge(horizontal: Bool, size: Int, at: (Int) -> Int) -> EdgeReading {
        let maxLines = Int(Double(size) * Detector.maxBarFraction)
        let maxGap = max(2, size / Detector.subtitleGapDivisor)
        var depth = 0, gap = 0, i = 0
        var minMean = Double.infinity, maxMean = -Double.infinity, barLevel = 0.0, barColor = 0.0
        var reference: Double?, last = 0.0, stepped = false
        while i < maxLines {
            let l = line(horizontal: horizontal, index: at(i))
            if l.darkSegments >= Detector.darkSegmentsNeeded {
                if let reference, l.trimmedMean - reference > Detector.maxBarVariation {
                    stepped = l.trimmedMean - last >= Detector.abruptStep
                    if !stepped { return .unknown }
                    break
                }
                last = l.trimmedMean
                reference = reference ?? l.trimmedMean
                minMean = min(minMean, l.trimmedMean)
                maxMean = max(maxMean, l.trimmedMean)
                barLevel = max(barLevel, l.level)
                barColor = max(barColor, l.color)
                depth = i + 1
                gap = 0
            } else if depth > 0, l.darkSegments >= Detector.subtitleDarkSegments, gap < maxGap {
                gap += 1
            } else {
                break
            }
            i += 1
        }
        if depth == 0 { return .none }
        if i >= maxLines { return .unknown }
        if maxMean - minMean > Detector.maxBarVariation { return .unknown }
        if stepped, maxMean - minMean > Detector.maxBarVariation / 2 { return .unknown }
        var inner = 0.0, innerColor = 0.0, innerShare = 0.0
        for k in depth..<min(depth + Detector.boundaryLines, size) {
            let l = line(horizontal: horizontal, index: at(k))
            inner = max(inner, l.level)
            innerColor = max(innerColor, l.color)
            innerShare = max(innerShare, l.litShare)
        }
        let lit = inner >= Detector.minPictureLevel && inner - barLevel >= Detector.minContrast
        let colored = innerColor >= Detector.minPictureColor && innerColor - barColor >= Detector.minColorContrast
        guard (lit || colored) && innerShare >= Detector.minLitShare else {
            return .likelyBar(Double(depth) / Double(size))
        }
        return .bar(Double(depth) / Double(size))
    }
}
