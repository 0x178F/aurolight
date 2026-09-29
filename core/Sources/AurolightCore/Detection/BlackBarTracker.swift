public struct BlackBarTracker: Sendable {
    public private(set) var insets = EdgeValues.uniform(0)

    static let growSeconds = 1.0
    static let growFrames = 8
    static let regrowSeconds = 1.0
    // growFrames stalled frames can never add up to growSeconds.
    static let maxStep = growSeconds / Double(growFrames)
    static let sameReadingTolerance = 0.01
    static let minInsetChange = 0.003
    // Growing by a row or two gains nothing and makes a noisy edge flicker between neighboring rows.
    static let minGrowth = sameReadingTolerance
    static let oppositeEdgeTolerance = 0.012
    static let maxNotchFraction = 0.06

    /// Readings within sameReadingTolerance of the first one. Anchored, so a slow drift can't carry old evidence
    /// to a new edge, and applied at its lowest reading, so a one-frame spike never crops.
    private struct Pending {
        let anchor: Double
        var value: Double
        var seconds = 0.0
        var frames = 0

        init(_ value: Double) {
            anchor = value
            self.value = value
        }
    }

    private var pending: [ScreenEdge: Pending] = [:]
    private var dropped: [ScreenEdge: (value: Double, time: Double)] = [:]
    private var lastTime: Double?

    public init() {}

    public mutating func update(with reading: BarReading, at time: Double) -> Bool {
        let dt = lastTime.map { min(max(time - $0, 0), Self.maxStep) } ?? 0
        lastTime = time
        var validated = Self.validate(reading)
        for edge in ScreenEdge.allCases where reading[edge] == .none { validated[edge] = .none }

        var changed = false
        for edge in ScreenEdge.allCases {
            let value: Double
            switch validated[edge] {
            case .unknown, .likelyBar:  // a matched likely bar was already promoted by validation
                pending[edge] = nil
                continue
            case .none: value = 0
            case let .bar(v): value = v
            }
            var p = pending[edge] ?? Pending(value)
            if abs(p.anchor - value) > Self.sameReadingTolerance { p = Pending(value) }
            if p.frames > 0 { p.seconds += dt }
            p.frames += 1
            p.value = min(p.value, value)
            pending[edge] = p

            let change = p.value - insets[edge]
            guard change < -Self.minInsetChange || change > Self.minGrowth else { continue }
            let growing = change > 0
            let returning =
                dropped[edge].map {
                    time - $0.time <= Self.regrowSeconds && abs($0.value - p.value) <= Self.sameReadingTolerance
                } ?? false
            let ready = !growing || returning || (p.seconds >= Self.growSeconds && p.frames >= Self.growFrames)
            if ready {
                if !growing { dropped[edge] = (insets[edge], time) }
                insets[edge] = p.value
                changed = true
            }
        }
        return changed
    }

    static func validate(_ reading: BarReading) -> BarReading {
        var out = reading
        func check(_ a: ScreenEdge, _ b: ScreenEdge, notch: ScreenEdge?) {
            switch (out[a], out[b]) {
            case let (.bar(x), .bar(y)) where abs(x - y) <= oppositeEdgeTolerance:
                return
            case let (.bar(x), .likelyBar(y)) where abs(x - y) <= oppositeEdgeTolerance:
                out[b] = .bar(y)
            case let (.likelyBar(x), .bar(y)) where abs(x - y) <= oppositeEdgeTolerance:
                out[a] = .bar(x)
            case (.none, .none):
                return
            case let (.bar(x), .none) where a == notch && x <= maxNotchFraction:
                return
            default:
                out[a] = .unknown
                out[b] = .unknown
            }
        }
        check(.top, .bottom, notch: .top)
        check(.left, .right, notch: nil)
        return out
    }
}
