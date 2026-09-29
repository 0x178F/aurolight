/// Adalight wire format: "Ada" + count-1 (hi, lo) + checksum (hi ^ lo ^ 0x55) + RGB bytes.
public enum Adalight {
    public static let magic: [UInt8] = Array("Ada".utf8)
    public static let maxLEDs = 65_536

    public static func frame(rgb: [UInt8]) -> [UInt8] {
        precondition(rgb.count >= 3 && rgb.count.isMultiple(of: 3), "rgb must contain 3 bytes per LED")
        precondition(rgb.count / 3 <= maxLEDs, "the header can't count more than \(maxLEDs) LEDs")
        let n = rgb.count / 3 - 1
        let hi = UInt8((n >> 8) & 0xFF)
        let lo = UInt8(n & 0xFF)
        return magic + [hi, lo, hi ^ lo ^ 0x55] + rgb
    }
}
