import Accelerate
import AurolightCore
import CoreMedia
import Foundation
import Synchronization

final class AudioAnalyzer: Sendable {
    private struct Published {
        var levels = AudioLevels.silent
        var hopTime = 0.0
        var resetRequested = false
    }

    private struct Analysis {
        var analyzer: AudioBandAnalyzer
        var pendingStartTime = 0.0
        var nextSampleTime: Double?
    }

    private let published = Mutex(Published())
    private let analysis: Mutex<Analysis>

    private static let maxDrift = 0.1

    init() {
        analysis = Mutex(Analysis(analyzer: AudioBandAnalyzer(sampleRate: Double(ScreenCapture.audioSampleRate))))
    }

    var current: AudioLevels {
        var (levels, hopTime) = published.withLock { ($0.levels, $0.hopTime) }
        guard !levels.history.isEmpty else { return levels }
        let age = Self.hostNow() - hopTime
        guard age < Self.staleAfter else { return .silent }
        levels.newestAge = min(max(age, 0), 0.1)
        return levels
    }

    private static let staleAfter = 1.0

    private static func hostNow() -> Double {
        CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }

    func reset() {
        published.withLock {
            $0.levels = .silent
            $0.resetRequested = true
        }
    }

    func process(_ sampleBuffer: CMSampleBuffer) {
        let resetRequested = published.withLock { state in
            defer { state.resetRequested = false }
            return state.resetRequested
        }
        guard let samples = Self.monoSamples(sampleBuffer), !samples.isEmpty else { return }
        let timestamp = sampleBuffer.presentationTimeStamp
        let result = analysis.withLock { state -> (AudioLevels, Double)? in
            if resetRequested {
                state.analyzer.reset()
                state.pendingStartTime = 0
                state.nextSampleTime = nil
            }
            let rate = state.analyzer.sampleRate
            if timestamp.isValid {
                let start = timestamp.seconds
                if state.analyzer.pendingCount == 0 || abs(start - (state.nextSampleTime ?? start)) > Self.maxDrift {
                    state.pendingStartTime = start - Double(state.analyzer.pendingCount) / rate
                }
                state.nextSampleTime = start + Double(samples.count) / rate
            }
            let hops = state.analyzer.append(samples)
            guard hops > 0 else { return nil }
            state.pendingStartTime += Double(hops) * state.analyzer.hopSeconds
            return (state.analyzer.levels, state.pendingStartTime)
        }
        guard let (levels, hopTime) = result else { return }
        published.withLock {
            $0.levels = levels
            $0.hopTime = hopTime
        }
    }

    private static func monoSamples(_ sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let format = sampleBuffer.formatDescription,
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
            asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32
        else { return nil }

        var listSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &listSize, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard listSize > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: listSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let listPointer = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        guard
            CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: listPointer, bufferListSize: listSize,
                blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer)
                == noErr
        else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(listPointer)
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, !buffers.isEmpty else { return nil }
        var mono = [Float](repeating: 0, count: frames)
        var channels = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let perFrame = max(Int(buffer.mNumberChannels), 1)
            let samples = data.assumingMemoryBound(to: Float.self)
            let available = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / perFrame
            for channel in 0..<perFrame {
                for i in 0..<min(frames, available) { mono[i] += samples[i * perFrame + channel] }
            }
            channels += perFrame
        }
        guard channels > 0 else { return nil }
        if channels > 1 { vDSP.multiply(1 / Float(channels), mono, result: &mono) }
        return mono
    }
}
