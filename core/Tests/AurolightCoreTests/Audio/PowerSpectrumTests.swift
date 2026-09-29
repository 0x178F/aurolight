import Foundation
import Testing

@testable import AurolightCore

struct PowerSpectrumTests {
    let n = 64

    @Test func aCosineLandsInItsBin() {
        // A cos(2π k i / n) has |X[k]| = A n / 2 and nothing elsewhere.
        let x = (0..<n).map { 0.8 * cos(2 * .pi * 5 * Double($0) / Double(n)) }
        let power = PowerSpectrum(size: n).power(of: x)
        #expect(power.count == n / 2)
        #expect(abs(power[5] - pow(0.8 * Double(n) / 2, 2)) < 1e-9)
        #expect(power.indices.filter { $0 != 5 }.allSatisfy { power[$0] < 1e-9 })
    }

    @Test func matchesADirectDFT() {
        let x = (0..<n).map { i in sin(Double(i) * 0.7) + 0.3 * cos(Double(i * i) * 0.11) }
        let power = PowerSpectrum(size: n).power(of: x)
        for k in 0..<n / 2 {
            var re = 0.0, im = 0.0
            for (i, v) in x.enumerated() {
                re += v * cos(2 * .pi * Double(k * i) / Double(n))
                im -= v * sin(2 * .pi * Double(k * i) / Double(n))
            }
            #expect(abs(power[k] - (re * re + im * im)) < 1e-9)
        }
    }
}
