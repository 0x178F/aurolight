import Foundation

public struct AudioBandAnalyzer {
    static let fftSize = 2048
    static let hopSize = 512
    static let bands: [(low: Double, high: Double, weight: Double)] = [
        (40, 160, 1.0), (160, 2_500, 1.4), (2_500, 10_000, 2.0),
    ]
    static let historyLength = 200
    static let referenceFloor = 0.003
    static let referenceRise = 0.05
    static let referenceFall = 4.0
    static let gateOpenLevel = -55.0
    static let gateCloseLevel = -60.0
    static let gateHoldSeconds = 0.2

    public let sampleRate: Double
    public let hopSeconds: Double
    public private(set) var levels = AudioLevels.silent

    private let spectrum = PowerSpectrum(size: Self.fftSize)
    private let window: [Double]
    private let windowRMS: Double
    private let bandBins: [ClosedRange<Int>]
    private var buffer: [Float]
    private var pending: [Float] = []
    private var reference = referenceFloor
    private var smoothed = [Double](repeating: 0, count: Self.bands.count)
    private var recentAverage = [Double](repeating: 0, count: Self.bands.count)
    private var gateOpen = false
    private var quietSeconds = 0.0
    private var history: [AudioLevels.Bands] = []

    public init(sampleRate: Double = 48_000) {
        precondition(sampleRate >= 2 * Self.bands[Self.bands.count - 1].high, "sample rate too low for the treble band")
        self.sampleRate = sampleRate
        hopSeconds = Double(Self.hopSize) / sampleRate
        window = (0..<Self.fftSize).map { 0.5 * (1 - cos(2 * .pi * Double($0) / Double(Self.fftSize))) }
        windowRMS = Self.rms(window)
        buffer = [Float](repeating: 0, count: Self.fftSize)
        let binWidth = sampleRate / Double(Self.fftSize)
        bandBins = Self.bands.map { band in
            max(
                1, Int((band.low / binWidth).rounded()))...min(
                    Self.fftSize / 2 - 1, Int((band.high / binWidth).rounded()))
        }
    }

    public var pendingCount: Int { pending.count }

    @discardableResult
    public mutating func append(_ samples: [Float]) -> Int {
        pending.append(contentsOf: samples)
        var hops = 0
        while pending.count >= Self.hopSize {
            buffer.removeFirst(Self.hopSize)
            buffer.append(contentsOf: pending.prefix(Self.hopSize))
            pending.removeFirst(Self.hopSize)
            analyzeHop()
            hops += 1
        }
        return hops
    }

    public mutating func reset() {
        self = AudioBandAnalyzer(sampleRate: sampleRate)
    }

    private mutating func analyzeHop() {
        let n = Double(Self.fftSize)
        let power = spectrum.power(of: zip(buffer, window).map { Double($0) * $1 })

        // One-sided spectrum (×2), undoing the window's energy loss.
        let scale = n * n * windowRMS * windowRMS / 2
        let amplitudes = bandBins.enumerated().map { band, bins in
            (power[bins].reduce(0, +) / scale).squareRoot() * Self.bands[band].weight
        }

        let loudest = amplitudes.max() ?? 0
        let tau = loudest > reference ? Self.referenceRise : Self.referenceFall
        reference = max(reference + (loudest - reference) * alpha(tau), Self.referenceFloor)

        let rms = Self.rms(buffer.map(Double.init))
        let dbfs = 20 * log10(max(rms, 1e-9))
        if dbfs > Self.gateOpenLevel {
            gateOpen = true
            quietSeconds = 0
        } else if dbfs < Self.gateCloseLevel {
            quietSeconds += hopSeconds
            if quietSeconds > Self.gateHoldSeconds { gateOpen = false }
        }

        for band in amplitudes.indices {
            let amplitude = amplitudes[band]
            recentAverage[band] += (amplitude - recentAverage[band]) * alpha(1.0)
            let level = min(amplitude / reference, 1)
            let punch = min(
                max((amplitude - recentAverage[band]) / max(reference - recentAverage[band], reference * 0.2), 0), 1)
            let target = gateOpen ? min(0.3 * pow(level, 1.5) + 0.9 * punch, 1) : 0
            let tau = target > smoothed[band] ? 0.015 : 0.15
            smoothed[band] += (target - smoothed[band]) * alpha(tau)
        }

        assert(Self.bands.count == 3, "AudioLevels.Bands has exactly bass, mid and treble")
        history.insert(AudioLevels.Bands(bass: smoothed[0], mid: smoothed[1], treble: smoothed[2]), at: 0)
        if history.count > Self.historyLength { history.removeLast() }
        levels = AudioLevels(history: history, historyInterval: hopSeconds)
    }

    private static func rms(_ values: [Double]) -> Double {
        (values.reduce(0) { $0 + $1 * $1 } / Double(values.count)).squareRoot()
    }

    private func alpha(_ tau: Double) -> Double {
        1 - exp(-hopSeconds / tau)
    }
}
