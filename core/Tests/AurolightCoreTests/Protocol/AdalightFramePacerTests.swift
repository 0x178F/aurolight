import Testing

@testable import AurolightCore

struct AdalightFramePacerTests {
    let red: [UInt8] = [255, 0, 0]
    let blue: [UInt8] = [0, 0, 255]

    func sentRed() -> AdalightFramePacer {
        var pacer = AdalightFramePacer(baudRate: 115_200, openedAt: 0)
        pacer.acknowledge()
        pacer.didSend(red, at: 10)
        return pacer
    }

    @Test func waitsForTheBoardToBoot() {
        let pacer = AdalightFramePacer(baudRate: 115_200, openedAt: 0)
        #expect(!pacer.shouldSend(red, at: 1))
        #expect(pacer.shouldSend(red, at: AdalightFramePacer.bootDelay))
    }

    @Test func greetingEndsTheBootWaitEarly() {
        var pacer = AdalightFramePacer(baudRate: 115_200, openedAt: 0)
        pacer.acknowledge()
        #expect(pacer.shouldSend(red, at: 0.5))
    }

    @Test func nextFrameWaitsForTheAnswer() {
        var pacer = sentRed()
        #expect(!pacer.shouldSend(blue, at: 10.01))
        pacer.acknowledge()
        #expect(pacer.shouldSend(blue, at: 10.01))
    }

    @Test func lostAnswerResendsEvenAnUnchangedFrame() {
        let pacer = sentRed()
        let timeout = AdalightFramePacer.ackTimeout(bytes: red.count, baudRate: 115_200)
        #expect(!pacer.shouldSend(red, at: 10 + timeout * 0.9))
        #expect(pacer.shouldSend(red, at: 10 + timeout))
    }

    @Test func unchangedFramesOnlyGoOutAsKeepAlive() {
        var pacer = sentRed()
        pacer.acknowledge()
        #expect(!pacer.shouldSend(red, at: 10.5))
        #expect(pacer.shouldSend(blue, at: 10.5))
        #expect(pacer.shouldSend(red, at: 10 + AdalightFramePacer.keepAlive))
        #expect(pacer.lastFrame == red)
    }

    @Test func readyOnceAnsweredOrOverdue() {
        var pacer = sentRed()
        let timeout = AdalightFramePacer.ackTimeout(bytes: red.count, baudRate: 115_200)
        #expect(!pacer.isReady(at: 10.001))
        #expect(pacer.isReady(at: 10 + timeout))
        pacer.acknowledge()
        #expect(pacer.isReady(at: 10.001))
    }

    @Test func timeoutCoversTheFrameOnTheWire() {
        // 600 LEDs at 115200 baud take ~157 ms on the wire alone.
        let bytes = 600 * 3
        let wire = Double((bytes + 6) * 10) / 115_200
        #expect(AdalightFramePacer.ackTimeout(bytes: bytes, baudRate: 115_200) > wire + 0.018)
        #expect(
            AdalightFramePacer.ackTimeout(bytes: bytes, baudRate: 921_600)
                < AdalightFramePacer.ackTimeout(bytes: bytes, baudRate: 115_200))
    }
}
