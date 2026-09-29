import Foundation

extension ScreenSampler {
    struct Grid {
        struct Cell {
            var lr = 0.0, lg = 0.0, lb = 0.0
            var y = 0.0
            var peak = 0.0
            var brightest = 0.0
            var brightestColor = PackedColor()
            var samples = CellSamples()
            var linearPeak = 0.0
            var okL = 0.0, okA = 0.0, okB = 0.0
            var confidence = 0.0
            var bin = ScreenSampler.neutralBin
            var peakBucket = 0
            var litLevel = 0.0
            var hueBrightness = 0.0

            init() {}

            init(
                lr: Double, lg: Double, lb: Double, peak: Double, brightest: Double? = nil,
                brightestColor: PackedColor = PackedColor(), samples: CellSamples = CellSamples()
            ) {
                (self.lr, self.lg, self.lb, self.peak) = (lr, lg, lb, peak)
                self.brightest = brightest ?? peak
                self.brightestColor = brightestColor
                self.samples = samples
                y = RGB(r: lr, g: lg, b: lb).luma  // on linear light: luminance, not luma
                linearPeak = max(lr, lg, lb)
                (okL, okA, okB) = Oklab.fromLinear(r: lr, g: lg, b: lb)
                let chroma = (okA * okA + okB * okB).squareRoot()
                confidence = smoothstep(ScreenSampler.chromaRange.0, ScreenSampler.chromaRange.1, chroma)
                if confidence > 0 {
                    var hue = atan2(okB, okA) / (2 * .pi)
                    if hue < 0 { hue += 1 }
                    bin = min(Int(hue * Double(ScreenSampler.bins)), ScreenSampler.bins - 1)
                }
                let buckets = ScreenSampler.histogramBuckets
                peakBucket = min(Int(peak * Double(buckets)), buckets - 1)
                litLevel = smoothstep(ScreenSampler.litRange.0, ScreenSampler.litRange.1, y)
                hueBrightness = ScreenSampler.hueBrightnessWeight(y)
            }
        }

        static let cellSize = 4
        private(set) var columns = 0, rows = 0
        var cells: [Cell] = []
        // Cells as loaded, before the overlay tracker fills any in, keyed by their exact sampled pixels.
        private var loaded: [Cell] = []
        private var keys: [SIMD4<UInt32>] = []

        mutating func load(bgra base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) {
            let pixels = base.assumingMemoryBound(to: UInt8.self)
            let decode = SRGB.decodeTable
            columns = max(1, width / Self.cellSize)
            rows = max(1, height / Self.cellSize)
            if cells.count != columns * rows {
                cells = [Cell](repeating: Cell(), count: columns * rows)
                loaded = cells
                keys = [SIMD4<UInt32>](repeating: SIMD4(repeating: 0), count: columns * rows)
            }
            // Cells are whole by construction (columns and rows round down) once the frame holds one.
            let cacheable = width >= Self.cellSize && height >= Self.cellSize
            for cy in 0..<rows {
                for cx in 0..<columns {
                    let index = cy * columns + cx
                    let top = base + cy * Self.cellSize * bytesPerRow + cx * Self.cellSize * 4
                    let key =
                        cacheable
                        ? SIMD4(
                            top.loadUnaligned(as: UInt32.self), top.loadUnaligned(fromByteOffset: 8, as: UInt32.self),
                            top.loadUnaligned(fromByteOffset: 2 * bytesPerRow, as: UInt32.self),
                            top.loadUnaligned(fromByteOffset: 2 * bytesPerRow + 8, as: UInt32.self))
                        : SIMD4<UInt32>(repeating: 0)
                    // Captured pixels have alpha, so an all-zero key only stands for "not cached".
                    if key == keys[index], key != SIMD4(repeating: 0) {
                        cells[index] = loaded[index]
                        continue
                    }
                    keys[index] = key
                    var r = 0.0, g = 0.0, b = 0.0, peak = 0.0, brightest: UInt8 = 0, brightestColor = PackedColor(),
                        n = 0.0
                    var samples = CellSamples()
                    for y in stride(from: cy * Self.cellSize, to: min((cy + 1) * Self.cellSize, height), by: 2) {
                        let row = pixels + y * bytesPerRow
                        for x in stride(from: cx * Self.cellSize, to: min((cx + 1) * Self.cellSize, width), by: 2) {
                            let p = row + x * 4
                            r += decode[Int(p[2])]; g += decode[Int(p[1])]; b += decode[Int(p[0])]
                            let strongest = max(p[0], p[1], p[2])
                            peak += Double(strongest) / 255
                            if strongest > brightest {
                                brightest = strongest
                                brightestColor = PackedColor(blue: p[0], green: p[1], red: p[2])
                            }
                            samples.set(Int(n), blue: p[0], green: p[1], red: p[2])
                            n += 1
                        }
                    }
                    let cell =
                        n > 0
                        ? Cell(
                            lr: r / n, lg: g / n, lb: b / n, peak: peak / n, brightest: Double(brightest) / 255,
                            brightestColor: brightestColor, samples: samples) : Cell()
                    cells[index] = cell
                    loaded[index] = cell
                }
            }
        }
    }
}
