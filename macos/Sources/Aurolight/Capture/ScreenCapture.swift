import AurolightCore
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import Synchronization

enum ScreenCaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No display available to capture"
        }
    }
}

enum CaptureProfile: Equatable, Sendable {
    case video
    case audio
}

protocol CaptureSource: AnyObject, Sendable {
    func setHandlers(
        onFrame: @escaping @Sendable (_ frame: CVPixelBuffer, _ isRepeat: Bool) -> Void,
        onError: @escaping @Sendable (Error) -> Void,
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void)
    func start(displayID: CGDirectDisplayID, fps: Int, profile: CaptureProfile) async throws
    func stop() async
    func refreshFilter(displayID: CGDirectDisplayID) async throws
    func redeliverLastFrame()
}

final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate, CaptureSource {
    static let audioSampleRate = 48_000

    private struct Handlers {
        var frame: (@Sendable (CVPixelBuffer, Bool) -> Void)?
        var error: (@Sendable (Error) -> Void)?
        var audio: (@Sendable (CMSampleBuffer) -> Void)?
    }

    // `SCStream` is safe to call from any thread; it just isn't marked `Sendable`.
    private struct Owned {
        var stream: UncheckedSendable<SCStream>?
        var profile = CaptureProfile.video
    }

    // Frames are only read after capture, never written, so sharing one is safe.
    private struct Frames {
        var last: UncheckedSendable<CVPixelBuffer>?
        var number = 0
    }

    private let handlers = Mutex(Handlers())
    private let owned = Mutex(Owned())
    private let frames = Mutex(Frames())
    private let queue = DispatchQueue(label: "com.fatihakdogan.aurolight.capture", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.fatihakdogan.aurolight.audio", qos: .userInteractive)
    private static let settleRepeats = 24
    private static let settleInterval = DispatchTimeInterval.milliseconds(60)
    private static let lateRepeat = DispatchTimeInterval.seconds(Int(PictureRegionDetector.idleRelease) + 1)

    private let captureWidth = 480

    func setHandlers(
        onFrame: @escaping @Sendable (CVPixelBuffer, Bool) -> Void,
        onError: @escaping @Sendable (Error) -> Void,
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void
    ) {
        handlers.withLock { $0 = Handlers(frame: onFrame, error: onError, audio: onAudio) }
    }

    func start(displayID: CGDirectDisplayID, fps: Int, profile: CaptureProfile) async throws {
        await stop()

        let (display, filter) = try await Self.filter(for: displayID)

        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        switch profile {
        case .video:
            config.width = captureWidth
            config.height = max(1, captureWidth * display.height / max(display.width, 1))
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
            config.queueDepth = 5
            config.capturesAudio = false
        case .audio:
            config.width = 16
            config.height = 16
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.queueDepth = 3
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = Self.audioSampleRate
            config.channelCount = 1
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if profile == .audio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue) }
        let shared = UncheckedSendable(stream)
        owned.withLock { $0 = Owned(stream: shared, profile: profile) }
        do {
            try await stream.startCapture()
        } catch {
            owned.withLock { if $0.stream?.value === shared.value { $0.stream = nil } }
            throw error
        }
    }

    func refreshFilter(displayID: CGDirectDisplayID) async throws {
        guard let stream = owned.withLock({ $0.stream })?.value else { return }
        let (_, filter) = try await Self.filter(for: displayID)
        try await stream.updateContentFilter(filter)
    }

    static func snapshot(displayID: CGDirectDisplayID, width: Int) async throws -> CGImage {
        let (display, filter) = try await filter(for: displayID)
        let config = SCStreamConfiguration()
        config.width = width
        config.height = max(1, width * display.height / max(display.width, 1))
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func isFullScreenWindowShowing(displayID: CGDirectDisplayID) -> Bool {
        let display = CGDisplayBounds(displayID)
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return true }
        let pid = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                (window[kCGWindowOwnerPID as String] as? Int32) != pid,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap({ CGRect(dictionaryRepresentation: $0) })
            else { continue }
            let visible = bounds.intersection(display)
            guard visible.width * visible.height >= 0.1 * display.width * display.height else { continue }
            return bounds.insetBy(dx: -1, dy: -1).contains(display)
        }
        return false
    }

    private static let chromeLevels: Set<Int> = [
        Int(CGWindowLevelForKey(.dockWindow)),
        Int(CGWindowLevelForKey(.mainMenuWindow)),
        Int(CGWindowLevelForKey(.statusWindow)),
    ]

    private static func filter(for displayID: CGDirectDisplayID) async throws -> (SCDisplay, SCContentFilter) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard
            let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first
        else {
            throw ScreenCaptureError.noDisplay
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let excluded = content.windows.filter {
            $0.owningApplication?.processID == pid || chromeLevels.contains($0.windowLayer)
        }
        return (display, SCContentFilter(display: display, excludingWindows: excluded))
    }

    func stop() async {
        let stream = owned.withLock { state in
            defer { state.stream = nil }
            return state.stream
        }
        try? await stream?.value.stopCapture()
        frames.withLock { $0.last = nil }
    }

    func redeliverLastFrame() {
        queue.async { self.redeliver(ifStill: nil) }
    }

    @discardableResult
    private func redeliver(ifStill number: Int?) -> Bool {
        let frame = frames.withLock { state in
            number == nil || number == state.number ? state.last : nil
        }?.value
        guard let frame, owned.withLock({ $0.stream != nil && $0.profile == .video }),
            let onFrame = handlers.withLock({ $0.frame })
        else { return false }
        onFrame(frame, true)
        return true
    }

    private func settle(_ number: Int, remaining: Int) {
        guard remaining > 0 else {
            queue.asyncAfter(deadline: .now() + Self.lateRepeat) { [weak self] in self?.redeliver(ifStill: number) }
            return
        }
        queue.asyncAfter(deadline: .now() + Self.settleInterval) { [weak self] in
            guard let self, self.redeliver(ifStill: number) else { return }
            self.settle(number, remaining: remaining - 1)
        }
    }

    private func current(_ stream: SCStream) -> CaptureProfile? {
        let candidate = UncheckedSendable(stream)
        return owned.withLock { $0.stream?.value === candidate.value ? $0.profile : nil }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let profile = current(stream) else { return }
        if type == .audio {
            handlers.withLock { $0.audio }?(sampleBuffer)
            return
        }
        guard type == .screen, profile == .video,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: rawStatus) == .complete,
            let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        let frame = UncheckedSendable(pixelBuffer)
        let number = frames.withLock { state in
            state.last = frame
            state.number += 1
            return state.number
        }
        handlers.withLock { $0.frame }?(pixelBuffer, false)
        settle(number, remaining: Self.settleRepeats)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let candidate = UncheckedSendable(stream)
        let wasOwned = owned.withLock { state in
            guard state.stream?.value === candidate.value else { return false }
            state.stream = nil
            return true
        }
        if wasOwned { handlers.withLock { $0.error }?(error) }
    }
}
