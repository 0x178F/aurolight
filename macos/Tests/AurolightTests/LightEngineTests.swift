import AurolightCore
import Foundation
import Synchronization
import Testing

@testable import Aurolight

@MainActor
struct LightEngineTests {
    let layout = LEDLayout(top: 8, right: 4, bottom: 8, left: 4)

    func config(_ mode: LightMode) -> LightEngine.Config {
        .init(layout: layout, color: ColorSettings(), effects: EffectSettings(mode: mode))
    }

    func engine(
        _ mode: LightMode, capture: FakeCapture, output: FakeOutput? = nil
    ) -> (LightEngine, Recorder) {
        let engine = LightEngine(config: config(mode), capture: capture, openOutput: { _ in output })
        let faults = Recorder()
        engine.setHandlers(.init(fault: { _ in faults.record() }))
        return (engine, faults)
    }

    @Test func screenSyncCapturesVideoAndStopEndsIt() async throws {
        let capture = FakeCapture()
        let (engine, _) = engine(.screen, capture: capture)
        try await engine.start(displayID: 1, output: .preview)
        #expect(capture.state.withLock { $0.running } == .video)
        await engine.stop()
        #expect(capture.state.withLock { $0.running } == nil)
    }

    @Test func effectsNeedNoCapture() async throws {
        let capture = FakeCapture()
        let (engine, _) = engine(.aurora, capture: capture)
        try await engine.start(displayID: 1, output: .preview)
        #expect(capture.state.withLock { $0.starts }.isEmpty)
        await engine.stop()
    }

    @Test func aDisplayChangeRestartsCaptureOnTheNewDisplay() async throws {
        let capture = FakeCapture()
        let (engine, _) = engine(.screen, capture: capture)
        try await engine.start(displayID: 1, output: .preview)
        engine.displayConfigurationChanged(displayID: 2)
        #expect(await eventually { capture.state.withLock { $0.displayID == 2 && $0.running == .video } })
        #expect(capture.state.withLock { $0.starts } == [.video, .video])
        await engine.stop()
    }

    @Test func stoppingRightAfterADisplayChangeLeavesNoStreamRunning() async throws {
        let capture = FakeCapture(startDelay: .milliseconds(50))
        let (engine, _) = engine(.screen, capture: capture)
        try await engine.start(displayID: 1, output: .preview)
        engine.displayConfigurationChanged(displayID: 2)
        await engine.stop()
        #expect(capture.state.withLock { $0.running } == nil)
    }

    @Test func switchingModesSwitchesCapture() async throws {
        let capture = FakeCapture()
        let (engine, _) = engine(.screen, capture: capture)
        try await engine.start(displayID: 1, output: .preview)
        engine.update(config(.music))
        #expect(await eventually { capture.state.withLock { $0.running } == .audio })
        engine.update(config(.fire))
        #expect(await eventually { capture.state.withLock { $0.running } == nil })
        await engine.stop()
    }

    @Test func aFailedCaptureStartFaults() async throws {
        let capture = FakeCapture()
        capture.state.withLock { $0.failing = .audio }
        let (engine, faults) = engine(.fire, capture: capture)
        try await engine.start(displayID: 1, output: .preview)
        engine.update(config(.music))
        #expect(await eventually { faults.value > 0 })
        await engine.stop()
    }

    @Test func aModeLeftWhileItsCaptureWasStartingCantStopTheNewOne() async throws {
        let capture = FakeCapture(startDelay: .milliseconds(100))
        capture.state.withLock { $0.failing = .audio }
        let (engine, faults) = engine(.fire, capture: capture)
        try await engine.start(displayID: 1, output: .preview)
        engine.update(config(.music))
        engine.update(config(.fire))
        try await Task.sleep(for: .milliseconds(400))
        #expect(faults.value == 0)
        await engine.stop()
    }

    @Test func aFailedStartSupersededByAnotherModeStillStarts() async throws {
        let capture = FakeCapture(startDelay: .milliseconds(100))
        capture.state.withLock { $0.failing = .video }
        let (engine, faults) = engine(.screen, capture: capture)
        let starting = Task { try await engine.start(displayID: 1, output: .preview) }
        try await Task.sleep(for: .milliseconds(30))
        engine.update(config(.fire))
        try await starting.value
        try await Task.sleep(for: .milliseconds(200))
        #expect(faults.value == 0)
        #expect(capture.state.withLock { $0.running } == nil)
        await engine.stop()
    }

    @Test func whiteCalibrationNeedsNoCapture() async throws {
        let capture = FakeCapture()
        var calibrating = config(.screen)
        calibrating.testColor = RGB(r: 1, g: 1, b: 1)
        let (engine, _) = engine(.screen, capture: capture)
        engine.update(calibrating)
        try await engine.start(displayID: 1, output: .preview)
        #expect(capture.state.withLock { $0.starts }.isEmpty)
        engine.update(config(.screen))
        #expect(await eventually { capture.state.withLock { $0.running } == .video })
        await engine.stop()
    }

    @Test func framesReachTheControllerAndStopTurnsItOff() async throws {
        let output = FakeOutput()
        let (engine, _) = engine(.aurora, capture: FakeCapture(), output: output)
        engine.setPreviewVisible(false)
        try await engine.start(displayID: 1, output: .serial(path: "/dev/null", baudRate: 115_200))
        #expect(await eventually { output.frames.withLock { $0 } > 3 })
        await engine.stop()
        #expect(output.closed.withLock { $0 })
    }

    @Test func aLostControllerFaultsOnce() async throws {
        let output = FakeOutput()
        let (engine, faults) = engine(.aurora, capture: FakeCapture(), output: output)
        try await engine.start(displayID: 1, output: .serial(path: "/dev/null", baudRate: 115_200))
        output.failing.withLock { $0 = true }
        #expect(await eventually { faults.value == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(faults.value == 1)
        await engine.stop()
    }

    @Test func aFaultFromAStoppedSessionIsDropped() async throws {
        let output = FakeOutput()
        let (engine, faults) = engine(.aurora, capture: FakeCapture(), output: output)
        try await engine.start(displayID: 1, output: .serial(path: "/dev/null", baudRate: 115_200))
        output.failing.withLock { $0 = true }
        // The failing tick may still be in flight.
        await engine.stop()
        try await Task.sleep(for: .milliseconds(200))
        #expect(faults.value == 0)
    }

    @Test func withoutControllerOrWindowNothingRenders() async throws {
        let previews = Recorder()
        let engine = LightEngine(config: config(.aurora), capture: FakeCapture(), openOutput: { _ in nil })
        engine.setHandlers(.init(preview: { _ in previews.record() }))
        engine.setPreviewVisible(false)
        try await engine.start(displayID: 1, output: .preview)
        try await Task.sleep(for: .milliseconds(300))
        #expect(previews.value == 0)
        engine.setPreviewVisible(true)
        #expect(await eventually { previews.value > 0 })
        await engine.stop()
    }
}
