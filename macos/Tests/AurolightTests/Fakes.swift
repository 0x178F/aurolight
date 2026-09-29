import CoreMedia
import CoreVideo
import Foundation
import Synchronization

@testable import Aurolight

final class FakeCapture: CaptureSource {
    struct State {
        var running: CaptureProfile?
        var displayID: CGDirectDisplayID?
        var starts: [CaptureProfile] = []
        var stops = 0
        var failing: CaptureProfile?
    }

    struct Failure: Error {}

    let state = Mutex(State())
    let startDelay: Duration

    init(startDelay: Duration = .zero) {
        self.startDelay = startDelay
    }

    func setHandlers(
        onFrame: @escaping @Sendable (CVPixelBuffer, Bool) -> Void,
        onError: @escaping @Sendable (Error) -> Void,
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void
    ) {}

    func start(displayID: CGDirectDisplayID, fps: Int, profile: CaptureProfile) async throws {
        await stop()
        try? await Task.sleep(for: startDelay)
        try state.withLock { state in
            state.starts.append(profile)
            if state.failing == profile { throw Failure() }
            state.running = profile
            state.displayID = displayID
        }
    }

    func stop() async {
        state.withLock { state in
            if state.running != nil { state.stops += 1 }
            state.running = nil
        }
    }

    func refreshFilter(displayID: CGDirectDisplayID) async throws {}
    func redeliverLastFrame() {}
}

final class FakeOutput: LightOutput, Sendable {
    let frames = Mutex(0)
    let closed = Mutex(false)
    let failing = Mutex(false)

    struct Unplugged: Error {}

    func submit(_ rgb: [UInt8]) throws {
        if failing.withLock({ $0 }) { throw Unplugged() }
        frames.withLock { $0 += 1 }
    }

    func keepAlive(ledCount: Int) throws {
        if failing.withLock({ $0 }) { throw Unplugged() }
    }

    func close(ledCount: Int) {
        closed.withLock { $0 = true }
    }
}

final class Recorder: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func record() {
        count.withLock { $0 += 1 }
    }
}

@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
