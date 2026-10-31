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
    }

    struct Snapshot: Sendable {
        var frames: Int64 = 0
        var format: Format?
    }

    private let lock = OSAllocatedUnfairLock(initialState: Snapshot())

    var snapshot: Snapshot {
        lock.withLock { $0 }
    }

    /// Called from `prepare`, which is not the real-time thread but must still
    /// stay allocation-free, so values are copied in place.
    func notePrepared(sampleRate: Double, channelCount: Int, isInterleaved: Bool) {
        lock.withLock {
            $0.format = Format(
                sampleRate: sampleRate,
                channelCount: channelCount,
                isInterleaved: isInterleaved
            )
        }
    }

    func noteProcessed(frames: Int) {
        guard frames > 0 else { return }
        lock.withLockIfAvailable { $0.frames += Int64(frames) }
    }
}

/// Creates the tap and owns the C callback table. The storage is retained by
/// the tap's client info and released in `finalize`.
enum EQTap {
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
    let isInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
    eqTapStorage(tap).notePrepared(
        sampleRate: format.mSampleRate,
        channelCount: Int(format.mChannelsPerFrame),
        isInterleaved: isInterleaved
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
    eqTapStorage(tap).noteProcessed(frames: numberFramesOut.pointee)
}
#endif
