public struct AutoCaptureArea: Sendable {
    private var bars = BlackBarTracker()
    private var picture = PictureRegionDetector()
    public private(set) var insets = EdgeValues.uniform(0)

    public init() {}

    public mutating func reset() {
        self = AutoCaptureArea()
    }

    public mutating func update(
        bgra base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, at time: Double,
        allowsOffCenter: Bool
    ) -> Bool {
        let reading = BlackBarDetector.read(bgra: base, width: width, height: height, bytesPerRow: bytesPerRow)
        _ = bars.update(with: reading, at: time)
        _ = picture.update(
            bgra: base, width: width, height: height, bytesPerRow: bytesPerRow, at: time,
            allowsOffCenter: allowsOffCenter)
        let next = picture.insets ?? bars.insets
        guard next != insets else { return false }
        insets = next
        return true
    }

    public mutating func expire(at time: Double) -> Bool {
        guard picture.expire(at: time) else { return false }
        let next = bars.insets
        guard next != insets else { return false }
        insets = next
        return true
    }
}
