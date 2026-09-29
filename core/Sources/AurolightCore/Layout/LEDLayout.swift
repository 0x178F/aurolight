public enum Corner: String, Codable, CaseIterable, Sendable {
    case topLeft, topRight, bottomRight, bottomLeft
}

public enum StripDirection: String, Codable, CaseIterable, Sendable {
    case clockwise, counterClockwise
}

public struct LEDSlot: Equatable, Sendable {
    public let edge: ScreenEdge
    public let position: Double
    public let region: NormRect
}

public struct LEDLayout: Codable, Equatable, Sendable {
    public static let maxPerEdge = 300

    public var top: Int { didSet { top = Self.clamped(top) } }
    public var right: Int { didSet { right = Self.clamped(right) } }
    public var bottom: Int { didSet { bottom = Self.clamped(bottom) } }
    public var left: Int { didSet { left = Self.clamped(left) } }
    public var startCorner: Corner
    public var startOffset: Int
    public var direction: StripDirection
    public var insets: EdgeValues

    public static let minExtent = 0.1

    public init(
        top: Int = 48,
        right: Int = 20,
        bottom: Int = 0,
        left: Int = 20,
        startCorner: Corner = .bottomLeft,
        startOffset: Int = 0,
        direction: StripDirection = .clockwise,
        insets: EdgeValues = .uniform(0)
    ) {
        self.top = Self.clamped(top)
        self.right = Self.clamped(right)
        self.bottom = Self.clamped(bottom)
        self.left = Self.clamped(left)
        self.startCorner = startCorner
        self.startOffset = 0
        self.direction = direction
        self.insets = insets
        self.startOffset = normalizedOffset(startOffset)
    }

    private static func clamped(_ count: Int) -> Int { min(max(count, 0), maxPerEdge) }

    private enum CodingKeys: String, CodingKey {
        case top, right, bottom, left, startCorner, startOffset, direction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LEDLayout()
        self.init(
            top: c.decode(.top, default: d.top),
            right: c.decode(.right, default: d.right),
            bottom: c.decode(.bottom, default: d.bottom),
            left: c.decode(.left, default: d.left),
            startCorner: c.decode(.startCorner, default: d.startCorner),
            startOffset: c.decode(.startOffset, default: d.startOffset),
            direction: c.decode(.direction, default: d.direction)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(top, forKey: .top)
        try c.encode(right, forKey: .right)
        try c.encode(bottom, forKey: .bottom)
        try c.encode(left, forKey: .left)
        try c.encode(startCorner, forKey: .startCorner)
        try c.encode(startOffset, forKey: .startOffset)
        try c.encode(direction, forKey: .direction)
    }

    public var detectionArea: NormRect {
        func axis(_ a: Double, _ b: Double) -> (Double, Double) {
            let a = min(max(a, 0), 1), b = min(max(b, 0), 1)
            let limit = 1 - Self.minExtent
            guard a + b > limit else { return (a, b) }
            return (a * limit / (a + b), b * limit / (a + b))
        }
        let (left, right) = axis(insets.left, insets.right)
        let (top, bottom) = axis(insets.top, insets.bottom)
        return NormRect(x: left, y: top, width: 1 - left - right, height: 1 - top - bottom)
    }

    public var placedCount: Int { top + right + bottom + left }

    public func slots() -> [LEDSlot] {
        let ring = clockwiseRing()
        let n = ring.count
        guard n > 0 else { return [] }

        let corner = cornerIndex(startCorner)
        return (0..<n).map { i in
            let index =
                direction == .clockwise
                ? corner + startOffset + i
                : corner - 1 - startOffset - i
            return ring[((index % n) + n) % n]
        }
    }

    public mutating func makeStart(stripIndex index: Int) {
        startOffset = normalizedOffset(startOffset + index)
    }

    /// Keeps LED 0 in place: clockwise ring[c + off] = counter-clockwise ring[c - 1 - off'].
    public mutating func reverseDirection() {
        direction = direction == .clockwise ? .counterClockwise : .clockwise
        startOffset = normalizedOffset(-1 - startOffset)
    }

    private func normalizedOffset(_ value: Int) -> Int {
        let n = placedCount
        guard n > 0 else { return 0 }
        var offset = (value % n + n) % n
        if offset > n / 2 { offset -= n }
        return offset
    }

    private func clockwiseRing() -> [LEDSlot] {
        let depth = ScreenSampler.edgeDepth
        let t = top, r = right, b = bottom, l = left
        var ring: [LEDSlot] = []
        ring.reserveCapacity(t + r + b + l)

        for i in 0..<t {
            let w = 1 / Double(t)
            ring.append(
                LEDSlot(
                    edge: .top, position: (Double(i) + 0.5) * w,
                    region: NormRect(x: Double(i) * w, y: 0, width: w, height: depth)))
        }
        for i in 0..<r {
            let h = 1 / Double(r)
            ring.append(
                LEDSlot(
                    edge: .right, position: (Double(i) + 0.5) * h,
                    region: NormRect(x: 1 - depth, y: Double(i) * h, width: depth, height: h)))
        }
        for i in 0..<b {
            let w = 1 / Double(b)
            let j = Double(b - 1 - i)
            ring.append(
                LEDSlot(
                    edge: .bottom, position: (j + 0.5) * w,
                    region: NormRect(x: j * w, y: 1 - depth, width: w, height: depth)))
        }
        for i in 0..<l {
            let h = 1 / Double(l)
            let j = Double(l - 1 - i)
            ring.append(
                LEDSlot(
                    edge: .left, position: (j + 0.5) * h,
                    region: NormRect(x: 0, y: j * h, width: depth, height: h)))
        }
        let area = detectionArea
        return ring.map { slot in
            let r = slot.region
            return LEDSlot(
                edge: slot.edge, position: slot.position,
                region: NormRect(
                    x: area.x + r.x * area.width, y: area.y + r.y * area.height,
                    width: r.width * area.width, height: r.height * area.height))
        }
    }

    private func cornerIndex(_ corner: Corner) -> Int {
        let t = top, r = right, b = bottom
        switch corner {
        case .topLeft: return 0
        case .topRight: return t
        case .bottomRight: return t + r
        case .bottomLeft: return t + r + b
        }
    }
}
