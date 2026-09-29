public struct AdalightFramePacer: Sendable {
    public static let bootDelay = 3.5
    /// Well inside the firmware's 5 s idle timeout.
    public static let keepAlive = 1.0

    public let baudRate: Int
    public private(set) var lastFrame: [UInt8] = []

    private var awaitingAck = true
    private var ackDeadline: Double
    private var lastSendTime = -Double.infinity

    public init(baudRate: Int, openedAt now: Double) {
        self.baudRate = baudRate
        ackDeadline = now + Self.bootDelay
    }

    public mutating func acknowledge() {
        awaitingAck = false
    }

    public func isReady(at now: Double) -> Bool {
        !awaitingAck || now >= ackDeadline
    }

    public func shouldSend(_ bytes: [UInt8], at now: Double) -> Bool {
        if awaitingAck {
            // Past the deadline the ack got lost or garbled: resend, even an unchanged frame.
            return isReady(at: now)
        }
        return bytes != lastFrame || now >= lastSendTime + Self.keepAlive
    }

    public mutating func didSend(_ bytes: [UInt8], at now: Double) {
        awaitingAck = true
        ackDeadline = now + Self.ackTimeout(bytes: bytes.count, baudRate: baudRate)
        lastFrame = bytes
        lastSendTime = now
    }

    public static func ackTimeout(bytes: Int, baudRate: Int) -> Double {
        let wire = Double((bytes + 6) * 10) / Double(max(baudRate, 1))
        let strip = Double(bytes / 3) * 30e-6
        return wire + strip + 0.05
    }
}
