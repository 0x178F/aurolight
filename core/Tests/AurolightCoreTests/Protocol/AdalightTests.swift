import Testing

@testable import AurolightCore

struct AdalightTests {
    @Test func singleLEDHeader() {
        let frame = Adalight.frame(rgb: [1, 2, 3])
        #expect(frame == [0x41, 0x64, 0x61, 0x00, 0x00, 0x55, 1, 2, 3])
    }

    @Test func multiByteCount() {
        let frame = Adalight.frame(rgb: [UInt8](repeating: 0, count: 300 * 3))
        let header: [UInt8] = [0x01, 0x2B, 0x01 ^ 0x2B ^ 0x55]
        #expect(Array(frame[3...5]) == header)
        #expect(frame.count == 6 + 900)
    }

    @Test func largestCountFillsTheHeader() {
        let frame = Adalight.frame(rgb: [UInt8](repeating: 0, count: Adalight.maxLEDs * 3))
        let header: [UInt8] = [0xFF, 0xFF, 0xFF ^ 0xFF ^ 0x55]
        #expect(Array(frame[3...5]) == header)
    }
}
