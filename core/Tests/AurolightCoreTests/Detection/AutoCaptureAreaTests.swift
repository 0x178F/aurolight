import Testing

@testable import AurolightCore

struct AutoCaptureAreaTests {
    let width = 200, height = 120

    func frame(_ t: Int, box: (Int, Int, Int, Int), surround: UInt8) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                if x >= box.0, x < box.2, y >= box.1, y < box.3 {
                    pixels[o] = UInt8((x + y + t * 17) % 256)
                    pixels[o + 1] = UInt8((y * 5 + t * 29) % 256)
                    pixels[o + 2] = UInt8((x * 7 + t * 13) % 256)
                } else {
                    pixels[o] = surround; pixels[o + 1] = surround; pixels[o + 2] = surround
                }
            }
        }
        return pixels
    }

    func run(_ area: inout AutoCaptureArea, frames: Range<Int>, allowsOffCenter: Bool, _ make: (Int) -> [UInt8]) {
        for i in frames {
            _ = make(i).withUnsafeBytes {
                area.update(
                    bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4, at: Double(i) / 30,
                    allowsOffCenter: allowsOffCenter)
            }
        }
    }

    @Test func aVideoInAWindowIsFramedByItsWindow() {
        var area = AutoCaptureArea()
        run(&area, frames: 0..<120, allowsOffCenter: true) { frame($0, box: (40, 20, 150, 90), surround: 220) }
        #expect(abs(area.insets.left - 0.2) < 0.01 && abs(area.insets.right - 0.25) < 0.01)
        #expect(abs(area.insets.top - 20.0 / 120) < 0.02 && abs(area.insets.bottom - 30.0 / 120) < 0.02)
    }

    @Test func letterboxBarsComeFromTheBarDetector() {
        var area = AutoCaptureArea()
        run(&area, frames: 0..<120, allowsOffCenter: false) { frame($0, box: (0, 15, 200, 105), surround: 0) }
        #expect(area.insets == EdgeValues(top: 0.125, right: 0, bottom: 0.125, left: 0))
    }

    @Test func aStoppedWindowedVideoFallsBackToTheBars() {
        var area = AutoCaptureArea()
        run(&area, frames: 0..<120, allowsOffCenter: true) { frame($0, box: (40, 20, 150, 90), surround: 220) }
        #expect(area.insets != .uniform(0))
        let released = area.expire(at: 4 + PictureRegionDetector.idleRelease)
        #expect(released && area.insets == .uniform(0))
    }
}
