/// Finds the white the viewer sees as matching the screen, like an eye test: each round offers two whites
/// around the current guess and halves the step, first for warmth, then for tint.
public struct WhiteBalanceCalibration: Equatable, Sendable {
    public enum Phase: Sendable { case warmth, tint, done }

    private struct Search: Equatable, Sendable {
        var center: Double
        var step: Double
        let finest: Double
        let range: ClosedRange<Double>

        var options: [Double] {
            [max(center - step, range.lowerBound), min(center + step, range.upperBound)]
        }
        var isDone: Bool { step < finest }
        var rounds: Int {
            var step = step, count = 0
            while step >= finest {
                step /= 2
                count += 1
            }
            return count
        }
    }

    private static let initialWarmth = Search(
        center: WhiteBalance.neutralTemperature, step: 1500, finest: 150, range: WhiteBalance.temperatureRange)
    private static let initialTint = Search(center: 0, step: 0.4, finest: 0.05, range: -1...1)

    public static let rounds = initialWarmth.rounds + initialTint.rounds

    public private(set) var phase = Phase.warmth
    public private(set) var answered = 0
    private var warmth = initialWarmth
    private var tint = initialTint

    public init() {}

    public var result: WhiteBalance {
        WhiteBalance(temperature: warmth.center, tint: tint.center)
    }

    /// The white shown for option 0 or 1; the result once done.
    public func candidate(_ option: Int) -> WhiteBalance {
        switch phase {
        case .warmth: WhiteBalance(temperature: warmth.options[option], tint: tint.center)
        case .tint: WhiteBalance(temperature: warmth.center, tint: tint.options[option])
        case .done: result
        }
    }

    public mutating func choose(_ option: Int) {
        advance { $0.center = $0.options[option] }
    }

    /// Neither looks closer: keep the guess and compare finer.
    public mutating func chooseNeither() {
        advance { _ in }
    }

    public mutating func finish() {
        phase = .done
    }

    private mutating func advance(_ move: (inout Search) -> Void) {
        switch phase {
        case .warmth:
            move(&warmth)
            warmth.step /= 2
            if warmth.isDone { phase = .tint }
        case .tint:
            move(&tint)
            tint.step /= 2
            if tint.isDone { phase = .done }
        case .done: return
        }
        answered += 1
    }
}
