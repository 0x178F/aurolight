extension ScreenSampler {
    public static let sceneCutThreshold = 0.25

    public static func isSceneCut(
        from previous: [RGB], to current: [RGB],
        threshold: Double = sceneCutThreshold
    ) -> Bool {
        guard previous.count == current.count, !current.isEmpty else { return false }
        let total = zip(previous, current).reduce(0.0) {
            $0 + abs($1.0.r - $1.1.r) + abs($1.0.g - $1.1.g) + abs($1.0.b - $1.1.b)
        }
        return total / Double(current.count * 3) > threshold
    }
}
