import AurolightCore
import CoreVideo
import Foundation
import Synchronization
import VideoToolbox

// Lock order: `shared` may be taken inside `sampling` or `output`, never the other way round.
final class LightEngine: Sendable {
    struct Config: Equatable {
        var layout: LEDLayout
        var color: ColorSettings
        var effects: EffectSettings
        var whiteBalance = WhiteBalance.neutral
        var testColor: RGB?
    }

    struct Handlers {
        var preview: (@MainActor @Sendable ([RGB]) -> Void)?
        var fault: (@MainActor @Sendable (Error) -> Void)?
        var thumbnail: (@MainActor @Sendable (CGImage) -> Void)?
        var detectedArea: (@MainActor @Sendable (EdgeValues) -> Void)?
    }

    private let shared: Mutex<Shared>
    private let sampling = Mutex(Sampling())
    private let output = Mutex(Output())
    private let capture: CaptureSource
    private let openOutput: @Sendable (OutputConfiguration) throws -> LightOutput?
    private let queue = DispatchQueue(label: "com.fatihakdogan.aurolight.output", qos: .userInteractive)
    private let audio = AudioAnalyzer()

    static let frameRate = 30
    private static let previewInterval = Duration.milliseconds(66)
    private static let thumbnailInterval = Duration.milliseconds(200)

    init(
        config: Config, capture: CaptureSource = ScreenCapture(),
        openOutput: @escaping @Sendable (OutputConfiguration) throws -> LightOutput? = { try $0.open() }
    ) {
        var initial = Shared(config: config)
        initial.refreshSamplingLayout()
        shared = Mutex(initial)
        self.capture = capture
        self.openOutput = openOutput
        capture.setHandlers(
            onFrame: { [weak self] buffer, isRepeat in self?.sample(buffer, isRepeat: isRepeat) },
            onError: { [weak self] error in self?.captureFailed(error) },
            onAudio: { [audio] buffer in audio.process(buffer) })
    }

    func setHandlers(_ handlers: Handlers) {
        shared.withLock { $0.handlers = handlers }
    }

    static func captureProfile(for config: Config) -> CaptureProfile? {
        guard config.testColor == nil else { return nil }
        return switch config.effects.mode {
        case .screen: .video
        case .music: .audio
        default: nil
        }
    }

    func update(_ newConfig: Config) {
        let profile = Self.captureProfile(for: newConfig)
        let (needsResample, request) = shared.withLock { state in
            let old = state.config
            state.config = newConfig
            if newConfig.layout != old.layout {
                state.refreshSamplingLayout()
                state.samples = []
            }
            if newConfig.effects.mode != old.effects.mode { state.effectEpoch = .now() }
            let changed = profile != state.desiredProfile
            state.desiredProfile = profile
            return (
                newConfig.layout != old.layout || newConfig.color.immersion != old.color.immersion,
                changed && state.running ? state.requestCapture() : nil
            )
        }
        if needsResample { capture.redeliverLastFrame() }
        if let request { applyCapture(request) }
    }

    func setPreviewVisible(_ visible: Bool) {
        let cameBack = shared.withLock { state in
            defer { state.previewVisible = visible }
            return visible && !state.previewVisible
        }
        if cameBack {
            queue.async { self.output.withLock { $0.lastPreview = [] } }
            capture.redeliverLastFrame()
        }
    }

    func displayConfigurationChanged(displayID: CGDirectDisplayID) {
        let request = shared.withLock { state -> Int? in
            guard state.running else { return nil }
            state.displayID = displayID
            state.captureRestartRequested = true
            return state.requestCapture()
        }
        if let request { applyCapture(request) }
    }

    func refreshCaptureFilter() {
        enqueueCaptureStep { engine in
            let (applied, displayID) = engine.shared.withLock { ($0.appliedProfile, $0.displayID) }
            guard applied == .video else { return nil }
            try? await engine.capture.refreshFilter(displayID: displayID)
            return nil
        }
    }

    func start(displayID: CGDirectDisplayID, output configuration: OutputConfiguration) async throws {
        await stop()

        // Handed over to the output queue, which alone uses it from here on.
        let device = try openOutput(configuration).map(UncheckedSendable.init)
        await onQueue { self.output.withLock { $0.device = device } }

        let request = shared.withLock { state in
            state.displayID = displayID
            state.running = true
            state.session += 1
            state.hasOutput = device != nil
            state.desiredProfile = Self.captureProfile(for: state.config)
            return state.requestCapture()
        }
        // A failure is only this start's if no newer capture request superseded it.
        if let error = await syncCapture().value, shared.withLock({ $0.captureRequest == request }) {
            Log.capture.error("Capture failed to start: \(error.localizedDescription, privacy: .public)")
            await stop()
            throw error
        }

        shared.withLock { $0.effectEpoch = .now() }
        watchWindows()
        await onQueue { self.startTimer() }
        // Hold off App Nap: a throttled timer stops keep-alives and the firmware's idle timeout blanks.
        guard device != nil else { return }
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Driving the LED strip")
        let token = UncheckedSendable(activity)
        shared.withLock { $0.activity = token }
    }

    // Runs on the caller until it awaits, so the session ends the moment Stop is pressed and a fault still on its
    // way to the caller is dropped.
    nonisolated(nonsending) func stop() async {
        let (activity, watch, placedCount) = shared.withLock { state in
            state.running = false
            state.session += 1
            defer {
                state.activity = nil
                state.windowWatch = nil
            }
            return (state.activity, state.windowWatch, state.config.layout.placedCount)
        }
        if let activity { ProcessInfo.processInfo.endActivity(activity.value) }
        watch?.cancel()
        _ = await syncCapture().value
        await onQueue {
            self.output.withLock { state in
                state.timer?.cancel()
                state.timer = nil
                state.device?.value.close(ledCount: placedCount)
                state.device = nil
                state.renderer = LightFrameRenderer()
                state.lastPreview = []
            }
        }
        shared.withLock { state in
            state.samples = []
            state.hasOutput = false
        }
    }

    private func onQueue(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                work()
                continuation.resume()
            }
        }
    }

    @discardableResult
    private func enqueueCaptureStep(_ step: @escaping @Sendable (LightEngine) async -> Error?) -> Task<Error?, Never> {
        shared.withLock { state in
            let previous = state.captureChain
            let task = Task<Error?, Never> { [weak self] in
                _ = await previous?.value
                guard let self else { return nil }
                return await step(self)
            }
            state.captureChain = task
            return task
        }
    }

    private func syncCapture() -> Task<Error?, Never> {
        enqueueCaptureStep { engine in
            let (target, applied, displayID, restart) = engine.shared.withLock { state in
                defer { state.captureRestartRequested = false }
                return (
                    state.running ? state.desiredProfile : nil, state.appliedProfile, state.displayID,
                    state.captureRestartRequested
                )
            }
            guard target != applied || (restart && target != nil) else { return nil }
            do {
                switch target {
                case .video?:
                    engine.resetDetection()
                    try await engine.capture.start(displayID: displayID, fps: Self.frameRate, profile: .video)
                case .audio?:
                    engine.audio.reset()
                    try await engine.capture.start(displayID: displayID, fps: Self.frameRate, profile: .audio)
                case nil:
                    await engine.capture.stop()
                }
                engine.shared.withLock { state in
                    state.samples = []
                    state.appliedProfile = target
                }
                return nil
            } catch {
                await engine.capture.stop()
                engine.shared.withLock { $0.appliedProfile = nil }
                return error
            }
        }
    }

    private func applyCapture(_ request: Int) {
        let task = syncCapture()
        Task { [weak self] in
            guard let error = await task.value, let self else { return }
            if self.shared.withLock({ $0.running && $0.captureRequest == request }) { self.fault(error) }
        }
    }

    private func captureFailed(_ error: Error) {
        Log.capture.error("Capture stopped: \(error.localizedDescription, privacy: .public)")
        shared.withLock { state in
            state.appliedProfile = nil
            state.samples = []
        }
        fault(error)
    }

    private func sample(_ buffer: CVPixelBuffer, isRepeat: Bool) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }

        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        updateDetectedArea(base: base, width: width, height: height, bytesPerRow: bytesPerRow, isRepeat: isRepeat)
        let (layout, immersion, idle) = shared.withLock { ($0.samplingLayout, $0.config.color.immersion, $0.isIdle) }
        guard !idle else { return }

        let (result, cut) = sampling.withLock { state in
            let result = state.sampler.sample(
                bgra: base, width: width, height: height, bytesPerRow: bytesPerRow,
                layout: layout, immersion: immersion)
            let cut = ScreenSampler.isSceneCut(from: state.lastSamples, to: result)
            if cut { state.sampler.reset() }
            state.lastSamples = result
            return (result, cut)
        }
        shared.withLock { state in
            if layout == state.samplingLayout {
                state.samples = result
                if cut { state.cutPending = true }
            }
        }
        publishThumbnail(buffer, isRepeat: isRepeat)
    }

    private func resetDetection() {
        let handler = shared.withLock { state in
            state.detectedArea = .uniform(0)
            state.detectionResetRequested = true
            state.refreshSamplingLayout()
            return state.handlers.detectedArea
        }
        if let handler { deliver(.uniform(0), to: handler) }
    }

    private func updateDetectedArea(
        base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, isRepeat: Bool
    ) {
        let (resetRequested, fullScreen) = shared.withLock { state in
            defer { state.detectionResetRequested = false }
            return (state.detectionResetRequested, state.fullScreenWindowShowing)
        }
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        let area = sampling.withLock { state -> EdgeValues? in
            if resetRequested { state.autoArea.reset() }
            let changed =
                isRepeat
                ? state.autoArea.expire(at: now)
                : state.autoArea.update(
                    bgra: base, width: width, height: height, bytesPerRow: bytesPerRow, at: now,
                    allowsOffCenter: !fullScreen)
            return changed ? state.autoArea.insets : nil
        }
        guard let area else { return }
        let handler = shared.withLock { state in
            state.detectedArea = area
            state.refreshSamplingLayout()
            return state.handlers.detectedArea
        }
        if let handler { deliver(area, to: handler) }
    }

    private func watchWindows() {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let (applied, displayID) = self.shared.withLock { ($0.appliedProfile, $0.displayID) }
                if applied == .video {
                    let fullScreen = ScreenCapture.isFullScreenWindowShowing(displayID: displayID)
                    self.shared.withLock { $0.fullScreenWindowShowing = fullScreen }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        let previous = shared.withLock { state in
            defer { state.windowWatch = task }
            return state.windowWatch
        }
        previous?.cancel()
    }

    private func publishThumbnail(_ buffer: CVPixelBuffer, isRepeat: Bool) {
        guard let handler = shared.withLock({ $0.previewVisible ? $0.handlers.thumbnail : nil }) else { return }
        let now = ContinuousClock.now
        let due = sampling.withLock { state in
            if !isRepeat { state.thumbnailBehind = true }
            guard state.thumbnailBehind, state.lastThumbnail.map({ now - $0 >= Self.thumbnailInterval }) ?? true
            else { return false }
            state.lastThumbnail = now
            state.thumbnailBehind = false
            return true
        }
        guard due else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
        if let image { deliver(image, to: handler) }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(), repeating: .nanoseconds(1_000_000_000 / Self.frameRate), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.tick() }
        let previous = output.withLock { state in
            defer { state.timer = timer }
            return state.timer
        }
        previous?.cancel()
        timer.resume()
    }

    private func tick() {
        let snapshot = shared.withLock { state -> TickState? in
            guard state.running, !state.isIdle else { return nil }
            defer { state.cutPending = false }
            return TickState(
                config: state.config, samples: state.samples, epoch: state.effectEpoch, cut: state.cutPending,
                session: state.session)
        }
        guard let snapshot else { return }
        let config = snapshot.config
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - snapshot.epoch.uptimeNanoseconds) / 1e9
        let input = LightFrameRenderer.Input(
            layout: config.layout, color: config.color, effects: config.effects,
            samples: snapshot.samples, sceneCut: snapshot.cut, time: elapsed, audio: audio.current,
            whiteBalance: config.whiteBalance, testColor: config.testColor)
        let result = output.withLock { state -> Result<[RGB]?, Error> in
            do {
                if let frame = state.renderer.render(input) {
                    try state.device?.value.submit(frame.bytes)
                    return .success(frame.preview)
                }
                try state.device?.value.keepAlive(ledCount: config.layout.placedCount)
                return .success(nil)
            } catch {
                state.device = nil
                return .failure(error)
            }
        }
        switch result {
        case .success(let preview?): publishPreview(preview)
        case .success(nil): break
        case .failure(let error): fault(error, raisedIn: snapshot.session)
        }
    }

    private func publishPreview(_ preview: [RGB]) {
        guard let handler = shared.withLock({ $0.previewVisible ? $0.handlers.preview : nil }) else { return }
        let now = ContinuousClock.now
        let interval = output.withLock { $0.lastPreviewTime.map { now - $0 >= Self.previewInterval } ?? true }
        guard interval else { return }
        var quantized: [UInt8] = []
        quantized.reserveCapacity(preview.count * 3)
        for c in preview {
            quantized.append(ColorProcessor.byte(c.r))
            quantized.append(ColorProcessor.byte(c.g))
            quantized.append(ColorProcessor.byte(c.b))
        }
        let due = output.withLock { state in
            guard quantized != state.lastPreview else { return false }
            state.lastPreview = quantized
            state.lastPreviewTime = now
            return true
        }
        if due { deliver(preview, to: handler) }
    }

    private func fault(_ error: Error, raisedIn session: Int? = nil) {
        guard let handler = shared.withLock({ $0.handlers.fault }) else { return }
        deliver(error, to: handler, raisedIn: session)
    }

    /// Drops anything that arrives after the session it came from has ended.
    private func deliver<Value: Sendable>(
        _ value: Value, to handler: @escaping @MainActor @Sendable (Value) -> Void, raisedIn session: Int? = nil
    ) {
        let raisedIn = session ?? shared.withLock { $0.session }
        Task { @MainActor [weak self] in
            guard let self, self.shared.withLock({ $0.session }) == raisedIn else { return }
            handler(value)
        }
    }
}

extension LightEngine {
    fileprivate struct Shared {
        var config: Config
        var handlers = Handlers()
        var samplingLayout: LEDLayout
        var cutPending = false
        var samples: [RGB] = []
        var detectedArea = EdgeValues.uniform(0)
        var detectionResetRequested = false
        var fullScreenWindowShowing = true
        var windowWatch: Task<Void, Never>?
        var effectEpoch = DispatchTime.now()
        var running = false
        var session = 0
        var hasOutput = false
        var displayID = CGMainDisplayID()
        var previewVisible = true
        var desiredProfile: CaptureProfile?
        var appliedProfile: CaptureProfile?
        var captureRestartRequested = false
        var captureChain: Task<Error?, Never>?
        var captureRequest = 0
        // Opaque App Nap token, only handed back to `endActivity`.
        var activity: UncheckedSendable<NSObjectProtocol>?

        init(config: Config) {
            self.config = config
            samplingLayout = config.layout
        }

        var isIdle: Bool { !hasOutput && !previewVisible }

        mutating func requestCapture() -> Int {
            captureRequest += 1
            return captureRequest
        }

        mutating func refreshSamplingLayout() {
            var layout = config.layout
            layout.insets = detectedArea
            samplingLayout = layout
        }
    }

    fileprivate struct TickState {
        let config: Config
        let samples: [RGB]
        let epoch: DispatchTime
        let cut: Bool
        let session: Int
    }

    fileprivate struct Sampling {
        var sampler = ScreenSampler()
        var lastSamples: [RGB] = []
        var lastThumbnail: ContinuousClock.Instant?
        // A newer frame than the one shown came in; repeats only catch the preview up to it.
        var thumbnailBehind = false
        var autoArea = AutoCaptureArea()
    }

    fileprivate struct Output {
        var renderer = LightFrameRenderer()
        var device: UncheckedSendable<LightOutput>?
        var timer: DispatchSourceTimer?
        var lastPreview: [UInt8] = []
        var lastPreviewTime: ContinuousClock.Instant?
    }
}
