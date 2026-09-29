import Foundation

struct PowerSpectrum {
    let size: Int
    private let cosines: [Double]
    private let sines: [Double]
    private let bitReversed: [Int]

    init(size: Int) {
        precondition(size >= 2 && size & (size - 1) == 0, "size must be a power of two")
        self.size = size
        cosines = (0..<size / 2).map { cos(2 * .pi * Double($0) / Double(size)) }
        sines = (0..<size / 2).map { sin(2 * .pi * Double($0) / Double(size)) }
        let bits = size.trailingZeroBitCount
        bitReversed = (0..<size).map { i in
            (0..<bits).reduce(0) { $0 << 1 | (i >> $1) & 1 }
        }
    }

    /// |X[k]|² of the unnormalized DFT, for k in 0..<size / 2.
    func power(of samples: [Double]) -> [Double] {
        precondition(samples.count == size)
        var re = bitReversed.map { samples[$0] }
        var im = [Double](repeating: 0, count: size)
        var length = 2
        while length <= size {
            let half = length / 2, step = size / length
            for start in stride(from: 0, to: size, by: length) {
                for k in 0..<half {
                    let wr = cosines[k * step], wi = -sines[k * step]
                    let a = start + k, b = a + half
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                }
            }
            length *= 2
        }
        return (0..<size / 2).map { re[$0] * re[$0] + im[$0] * im[$0] }
    }
}
