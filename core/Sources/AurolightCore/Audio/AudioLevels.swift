public struct AudioLevels: Equatable, Sendable {
    public struct Bands: Equatable, Sendable {
        public var bass: Double
        public var mid: Double
        public var treble: Double

        public init(bass: Double, mid: Double, treble: Double) {
            self.bass = bass
            self.mid = mid
            self.treble = treble
        }

        public static let zero = Bands(bass: 0, mid: 0, treble: 0)
    }

    public var history: [Bands]
    public var historyInterval: Double
    public var newestAge: Double

    public init(history: [Bands] = [], historyInterval: Double = 0, newestAge: Double = 0) {
        self.history = history
        self.historyInterval = historyInterval
        self.newestAge = newestAge
    }

    public func bands(atAge age: Double) -> Bands {
        guard !history.isEmpty, historyInterval > 0 else { return .zero }
        let position = max(age - newestAge, 0) / historyInterval
        let i = Int(position)
        guard i < history.count - 1 else { return i < history.count ? history[i] : .zero }
        let t = position - Double(i)
        let a = history[i], b = history[i + 1]
        return Bands(
            bass: a.bass + (b.bass - a.bass) * t,
            mid: a.mid + (b.mid - a.mid) * t,
            treble: a.treble + (b.treble - a.treble) * t)
    }

    public static let silent = AudioLevels()
}
