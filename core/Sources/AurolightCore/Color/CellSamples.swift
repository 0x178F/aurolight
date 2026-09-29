struct CellSamples: Equatable, Sendable {
    static let count = 4
    private(set) var packed: UInt32 = 0

    mutating func set(_ index: Int, blue: UInt8, green: UInt8, red: UInt8) {
        let luma = (UInt32(blue) * 29 + UInt32(green) * 150 + UInt32(red) * 77) >> 8
        let shift = UInt32(8 * (index % Self.count))
        packed = packed & ~(0xFF << shift) | luma << shift
    }

    subscript(index: Int) -> Int { Int((packed >> UInt32(8 * index)) & 0xFF) }

    var mean: Int { (0..<Self.count).reduce(0) { $0 + self[$1] } / Self.count }

    var spread: Int {
        var low = 255, high = 0
        for i in 0..<Self.count {
            low = min(low, self[i])
            high = max(high, self[i])
        }
        return high - low
    }

    func matches(_ other: CellSamples, within: Int) -> Bool {
        (0..<Self.count).allSatisfy { abs(self[$0] - other[$0]) <= within }
    }

    func isClipped(dark: Int, light: Int) -> Bool {
        (0..<Self.count).allSatisfy { self[$0] <= dark } || (0..<Self.count).allSatisfy { self[$0] >= light }
    }
}

struct PackedColor: Equatable, Sendable {
    private(set) var packed: UInt32 = 0

    init() {}

    init(blue: UInt8, green: UInt8, red: UInt8) {
        packed = UInt32(blue) | UInt32(green) << 8 | UInt32(red) << 16
    }

    var blue: Int { Int(packed & 0xFF) }
    var green: Int { Int((packed >> 8) & 0xFF) }
    var red: Int { Int((packed >> 16) & 0xFF) }

    var luma: Int { (blue * 29 + green * 150 + red * 77) >> 8 }

    func isNeutral(spread: Int) -> Bool { max(blue, green, red) - min(blue, green, red) <= spread }

    func matches(_ other: PackedColor, within: Int) -> Bool {
        abs(blue - other.blue) <= within && abs(green - other.green) <= within && abs(red - other.red) <= within
    }
}
