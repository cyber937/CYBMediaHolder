//
//  MockMediaProbe.swift
//  CYBMediaHolderTests
//
//  Mock implementation of MediaProbe for testing purposes.
//

import Foundation
import CoreMedia
@testable import CYBMediaHolder

/// Mock probe implementation for testing.
///
/// Returns pre-configured descriptors without actual file access.
public struct MockMediaProbe: MediaProbe, Sendable {

    // MARK: - MediaProbe Properties

    public let identifier = "mock"
    public let displayName = "Mock Probe"
    public let supportedExtensions: Set<String> = ["mov", "mp4", "m4v"]
    public let supportedUTTypes: Set<String> = ["public.movie"]

    // MARK: - Configuration

    /// The descriptor to return on probe.
    public let mockDescriptor: MediaDescriptor?

    /// Error to throw on probe.
    public let probeError: MediaProbeError?

    /// Delay before returning result (for testing async behavior).
    public let probeDelay: TimeInterval

    /// Track probe calls.
    public private(set) var probeCallCount: Int = 0

    // MARK: - Initialization

    /// Creates a mock probe that returns a specific descriptor.
    public init(
        descriptor: MediaDescriptor? = nil,
        error: MediaProbeError? = nil,
        delay: TimeInterval = 0
    ) {
        self.mockDescriptor = descriptor
        self.probeError = error
        self.probeDelay = delay
    }

    /// Creates a mock probe with a default video descriptor.
    public static func defaultVideoProbe() -> MockMediaProbe {
        MockMediaProbe(descriptor: Self.createDefaultVideoDescriptor())
    }

    /// Creates a mock probe with a default audio descriptor.
    public static func defaultAudioProbe() -> MockMediaProbe {
        MockMediaProbe(descriptor: Self.createDefaultAudioDescriptor())
    }

    /// Creates a mock probe that fails with the given error.
    public static func failingProbe(error: MediaProbeError = .noTracksFound) -> MockMediaProbe {
        MockMediaProbe(error: error)
    }

    // MARK: - MediaProbe Implementation

    public func probe(locator: MediaLocator) async throws -> MediaDescriptor {
        if probeDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(probeDelay * 1_000_000_000))
        }

        if let error = probeError {
            throw error
        }

        guard let descriptor = mockDescriptor else {
            throw MediaProbeError.noTracksFound
        }

        return descriptor
    }

    // MARK: - Factory Methods

    /// Creates a default video descriptor for testing.
    public static func createDefaultVideoDescriptor(
        duration: Double = 60.0,
        width: Int = 1920,
        height: Int = 1080,
        frameRate: Float = 30.0,
        hasAudio: Bool = true
    ) -> MediaDescriptor {
        let container = ContainerInfo(
            format: "QuickTime",
            fileExtension: "mov"
        )

        let videoCodec = CodecInfo(fourCC: "avc1", displayName: "H.264/AVC")
        let videoTrack = VideoTrackDescriptor(
            id: 1,
            trackIndex: 0,
            codec: videoCodec,
            size: CGSize(width: width, height: height),
            displayAspectRatio: nil,
            nominalFrameRate: frameRate,
            minFrameDuration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            isVFR: false,
            colorInfo: .sdrRec709,
            timeRange: CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: duration, preferredTimescale: 600)
            ),
            timescale: 600,
            averageBitRate: 10_000_000
        )

        var audioTracks: [AudioTrackDescriptor] = []
        if hasAudio {
            let audioCodec = CodecInfo(fourCC: "aac ", displayName: "AAC")
            let audioTrack = AudioTrackDescriptor(
                id: 2,
                trackIndex: 0,
                codec: audioCodec,
                sampleRate: 48000,
                channelCount: 2,
                channelLayout: "Stereo",
                bitsPerSample: 16,
                averageBitRate: 256_000,
                timeRange: CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: duration, preferredTimescale: 600)
                ),
                languageCode: nil
            )
            audioTracks.append(audioTrack)
        }

        return MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [videoTrack],
            audioTracks: audioTracks,
            probeBackend: "Mock"
        )
    }

    /// Creates a default audio-only descriptor for testing.
    public static func createDefaultAudioDescriptor(
        duration: Double = 180.0,
        sampleRate: Double = 48000,
        channels: Int = 2
    ) -> MediaDescriptor {
        let container = ContainerInfo(
            format: "MPEG-4 Audio",
            fileExtension: "m4a"
        )

        let audioCodec = CodecInfo(fourCC: "aac ", displayName: "AAC")
        let audioTrack = AudioTrackDescriptor(
            id: 1,
            trackIndex: 0,
            codec: audioCodec,
            sampleRate: sampleRate,
            channelCount: channels,
            channelLayout: channels == 2 ? "Stereo" : "Mono",
            bitsPerSample: 16,
            averageBitRate: 256_000,
            timeRange: CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: duration, preferredTimescale: 600)
            ),
            languageCode: nil
        )

        return MediaDescriptor(
            mediaType: .audio,
            container: container,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [audioTrack],
            probeBackend: "Mock"
        )
    }
}
