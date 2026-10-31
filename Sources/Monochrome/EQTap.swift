// EQTap.swift: a pass-through MTAudioProcessingTap plus the state it hands to
// the main thread. Audio-thread callbacks touch only this file's storage.
#if canImport(AVFoundation)
import AVFoundation
import Foundation
import MediaToolbox
import MonochromeCore
import os

/// Shared between the real-time tap callbacks and the main thread. Every field
/// is behind a try-lock: the audio thread never waits, and a skipped update
/// only costs telemetry precision.
final class EQTapStorage: @unchecked Sendable {
    struct Format: Equatable, Sendable {
        var sampleRate: Double
        var channelCount: Int
        var isInterleaved: Bool
        var isFloat: Bool
    }

    struct Live: Sendable {
        var format: Format?
        var frames: Int64 = 0
        var peak: Double = 0
        var pending: EQSnapshot?
        var version: Int = 0
        var appliedVersion: Int = 0
    }

    struct Observation: Sendable {
        var format: Format?
        var frames: Int64
        var peak: Double
        var hasUnappliedSnapshot: Bool
    }

    private let lock = OSAllocatedUnfairLock(initialState: Live())
    /// Touched only by the tap callbacks: created in `prepare`, used in `process`.
    private var renderer: EQRenderer?
    private var appliedSampleRate: Double = 0

    var observation: Observation {
        lock.withLock {
            Observation(
                format: $0.format,
                frames: $0.frames,
                peak: $0.peak,
                hasUnappliedSnapshot: $0.version != $0.appliedVersion
            )
        }
    }

    /// Main thread: makes a snapshot the next buffer will pick up.
    func publish(_ snapshot: EQSnapshot) {
        lock.withLock {
            $0.pending = snapshot
            $0.version += 1
        }
    }

    /// Main thread: reads and clears the clip light.
    func takePeak() -> Double {
        lock.withLock {
            let peak = $0.peak
            $0.peak = 0
            return peak
        }
    }

    /// Called from `prepare`, which is not the real-time thread. The renderer
    /// allocates here, never inside `process`.
    func prepare(format: Format, rampSamples: Int) {
        lock.withLock {
            $0.format = format
            $0.appliedVersion = 0
        }
        appliedSampleRate = format.sampleRate
        renderer = format.isFloat
            ? EQRenderer(channelCount: format.channelCount, sampleRate: format.sampleRate)
            : nil
        if let renderer, let pending = lock.withLock({ $0.pending }) {
            renderer.update(pending, rampSamples: rampSamples)
            lock.withLock { $0.appliedVersion = $0.version }
        }
    }

    /// Audio thread. Pulls a pending snapshot without waiting, then renders in
    /// place. A non-float format leaves the samples untouched.
    func render(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int, rampSamples: Int) {
        guard frames > 0, let renderer else { return }

        if let snapshot = takePendingSnapshot() {
            renderer.update(snapshot, rampSamples: rampSamples)
        }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        if buffers.count == 1 {
            guard let data = buffers[0].mData else { return }
            renderer.processInterleaved(
                data.assumingMemoryBound(to: Float.self),
                frameCount: frames
            )
        } else {
            let channels = min(buffers.count, renderer.channelCount)
            withUnsafeTemporaryAllocation(of: UnsafeMutablePointer<Float>.self, capacity: channels) { scratch in
                guard let base = scratch.baseAddress else { return }
                for index in 0..<channels {
                    guard let data = buffers[index].mData else { return }
                    base[index] = data.assumingMemoryBound(to: Float.self)
                }
                renderer.processPlanar(base, channels: channels, frameCount: frames)
            }
        }

        let peak = renderer.takePeak()
        lock.withLockIfAvailable {
            if peak > $0.peak { $0.peak = peak }
        }
    }

    private func takePendingSnapshot() -> EQSnapshot? {
        lock.withLockIfAvailable { live -> EQSnapshot? in
            guard let pending = live.pending, live.version != live.appliedVersion else { return nil }
            live.appliedVersion = live.version
            return pending
        } ?? nil
    }

    func noteProcessed(frames: Int) {
        guard frames > 0 else { return }
        lock.withLockIfAvailable { $0.frames += Int64(frames) }
    }

    deinit {
        renderer = nil
    }
}

/// Creates the tap and owns the C callback table. The storage is retained by
/// the tap's client info and released in `finalize`.
enum EQTap {
    /// Long enough to hide a coefficient swap, short enough to feel immediate.
    static let rampSamples = 512

    static func make(storage: EQTapStorage) -> MTAudioProcessingTap? {
        let clientInfo = Unmanaged.passRetained(storage).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: eqTapInit,
            finalize: eqTapFinalize,
            prepare: eqTapPrepare,
            unprepare: eqTapUnprepare,
            process: eqTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )
        guard status == noErr, let tap else {
            // The retained client info would leak here, so balance it now.
            Unmanaged<EQTapStorage>.fromOpaque(clientInfo).release()
            playerLog.error("eq tap create failed status=\(status)")
            return nil
        }
        return tap
    }
}

private func eqTapStorage(_ tap: MTAudioProcessingTap) -> EQTapStorage {
    Unmanaged<EQTapStorage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}

private func eqTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func eqTapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<EQTapStorage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func eqTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let format = processingFormat.pointee
    let storage = eqTapStorage(tap)
    storage.prepare(
        format: EQTapStorage.Format(
            sampleRate: format.mSampleRate,
            channelCount: Int(max(format.mChannelsPerFrame, 1)),
            isInterleaved: (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
            isFloat: (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
                && format.mBitsPerChannel == 32
        ),
        rampSamples: EQTap.rampSamples
    )
}

private func eqTapUnprepare(_ tap: MTAudioProcessingTap) {}

private func eqTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberOfFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberOfFrames,
        bufferListInOut,
        flagsOut,
        nil,
        numberFramesOut
    )
    guard status == noErr else { return }
    let storage = eqTapStorage(tap)
    let frames = Int(numberFramesOut.pointee)
    storage.noteProcessed(frames: frames)
    storage.render(bufferListInOut, frames: frames, rampSamples: EQTap.rampSamples)
}
#endif
