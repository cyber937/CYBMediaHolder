//
//  Capability.swift
//  CYBMediaHolder
//
//  Declares what operations are available for a media item.
//  UI and Player use capabilities to determine available features.
//

import Foundation

/// Represents a specific capability that a media item may have.
///
/// Capabilities are derived from:
/// - Media descriptor (codec, format)
/// - Backend support (AVFoundation, FFmpeg, RAW SDK)
/// - Analysis state (waveform generated, keyframe index built)
///
/// ## Design Notes
/// - Capabilities are additive; new ones can be added without breaking
/// - UI should check capabilities before offering features
/// - Some capabilities may be "potentially available" (can be computed)
///
/// ## Future Extensions
/// - Plugin-provided capabilities (e.g., RED SDK)
/// - Remote capabilities (what can be done without downloading)
public struct Capability: OptionSet, Codable, Sendable, Hashable {

    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    // MARK: - Playback Capabilities

    /// Can play video frames.
    public static let videoPlayback = Capability(rawValue: 1 << 0)

    /// Can play audio.
    public static let audioPlayback = Capability(rawValue: 1 << 1)

    /// Supports random frame access (seeking).
    public static let randomFrameAccess = Capability(rawValue: 1 << 2)

    /// Supports frame-accurate seeking.
    public static let frameAccurateSeeking = Capability(rawValue: 1 << 3)

    /// Supports reverse playback.
    public static let reversePlayback = Capability(rawValue: 1 << 4)

    /// Supports variable speed playback.
    public static let variableSpeed = Capability(rawValue: 1 << 5)

    // MARK: - Analysis Capabilities (Available)

    /// Waveform data is available.
    public static let waveformAvailable = Capability(rawValue: 1 << 10)

    /// Peak data is available.
    public static let peakAvailable = Capability(rawValue: 1 << 11)

    /// Keyframe index is available.
    public static let keyframeIndexAvailable = Capability(rawValue: 1 << 12)

    /// Thumbnail index is available.
    public static let thumbnailIndexAvailable = Capability(rawValue: 1 << 13)

    // MARK: - Analysis Capabilities (Can Generate)

    /// Waveform can be generated.
    public static let waveformGeneratable = Capability(rawValue: 1 << 20)

    /// Peak data can be generated.
    public static let peakGeneratable = Capability(rawValue: 1 << 21)

    /// Keyframe index can be generated.
    public static let keyframeIndexGeneratable = Capability(rawValue: 1 << 22)

    /// Thumbnails can be generated.
    public static let thumbnailGeneratable = Capability(rawValue: 1 << 23)

    // MARK: - Color & HDR Capabilities

    /// Color profile information is available.
    public static let colorProfileInspection = Capability(rawValue: 1 << 30)

    /// HDR metadata is available.
    public static let hdrMetadata = Capability(rawValue: 1 << 31)

    /// HDR to SDR tone mapping is available.
    public static let hdrTonemapping = Capability(rawValue: 1 << 32)

    // MARK: - Backend Capabilities

    /// Backed by AVFoundation.
    public static let avFoundationBacked = Capability(rawValue: 1 << 40)

    /// Backed by FFmpeg (future).
    public static let ffmpegBacked = Capability(rawValue: 1 << 41)

    /// Backed by RAW SDK (e.g., RED, BRAW) (future).
    public static let rawBacked = Capability(rawValue: 1 << 42)

    // MARK: - Remote Capabilities (Future)

    /// Supports HTTP range requests.
    public static let remoteRangeReadable = Capability(rawValue: 1 << 50)

    /// Supports streaming playback.
    public static let streamable = Capability(rawValue: 1 << 51)

    /// Partial download/progressive playback.
    public static let progressiveDownload = Capability(rawValue: 1 << 52)

    // MARK: - Editing Capabilities

    /// Can extract frames as images.
    public static let frameExtraction = Capability(rawValue: 1 << 55)

    /// Can extract audio segments.
    public static let audioExtraction = Capability(rawValue: 1 << 56)

    /// Can be used in composition.
    public static let composable = Capability(rawValue: 1 << 57)

    // MARK: - Timecode Capabilities

    /// Explicit timecode data is available (from tmcd track or metadata).
    /// When this is set, the CoreNormalizedStore contains reliable timecode
    /// extracted from the media container.
    public static let timecodeAvailable = Capability(rawValue: 1 << 60)

    /// Timecode is inferable (estimated from duration/framerate, not explicit).
    /// When this is set, the timecode is a best-effort estimate (typically 00:00:00:00)
    /// and should be treated with lower confidence.
    public static let timecodeInferable = Capability(rawValue: 1 << 61)

    // MARK: - Convenience Sets

    /// Standard playback capabilities.
    public static let standardPlayback: Capability = [
        .videoPlayback, .audioPlayback, .randomFrameAccess
    ]

    /// Full playback capabilities.
    public static let fullPlayback: Capability = [
        .videoPlayback, .audioPlayback, .randomFrameAccess,
        .frameAccurateSeeking, .reversePlayback, .variableSpeed
    ]

    /// All analysis generation capabilities.
    public static let allAnalysisGeneratable: Capability = [
        .waveformGeneratable, .peakGeneratable,
        .keyframeIndexGeneratable, .thumbnailGeneratable
    ]

    /// All analysis available capabilities.
    public static let allAnalysisAvailable: Capability = [
        .waveformAvailable, .peakAvailable,
        .keyframeIndexAvailable, .thumbnailIndexAvailable
    ]
}

// MARK: - Capability Description

extension Capability: CustomStringConvertible {
    public var description: String {
        var names: [String] = []

        if contains(.videoPlayback) { names.append("videoPlayback") }
        if contains(.audioPlayback) { names.append("audioPlayback") }
        if contains(.randomFrameAccess) { names.append("randomFrameAccess") }
        if contains(.frameAccurateSeeking) { names.append("frameAccurateSeeking") }
        if contains(.waveformAvailable) { names.append("waveformAvailable") }
        if contains(.peakAvailable) { names.append("peakAvailable") }
        if contains(.keyframeIndexAvailable) { names.append("keyframeIndexAvailable") }
        if contains(.colorProfileInspection) { names.append("colorProfileInspection") }
        if contains(.hdrMetadata) { names.append("hdrMetadata") }
        if contains(.avFoundationBacked) { names.append("avFoundationBacked") }
        if contains(.rawBacked) { names.append("rawBacked") }
        if contains(.timecodeAvailable) { names.append("timecodeAvailable") }
        if contains(.timecodeInferable) { names.append("timecodeInferable") }

        return "Capability[\(names.joined(separator: ", "))]"
    }
}

// MARK: - Capability Calculator

/// Calculates capabilities from descriptor and backend information.
///
/// This is the central logic for determining what operations are available
/// for a given media item. Implemented as an enum with static methods since
/// it has no instance state - this is more idiomatic Swift than a singleton struct.
///
/// ## Usage
/// ```swift
/// let caps = CapabilityCalculator.calculate(
///     for: descriptor,
///     backend: "AVFoundation",
///     analysisState: state
/// )
/// ```
///
/// ## Future Extensions
/// - Plugin registry for backend capabilities
/// - Remote source capability detection
public enum CapabilityCalculator {

    /// Shared instance for backwards compatibility.
    /// - Note: Prefer calling static methods directly.
    @available(*, deprecated, message: "Use static methods directly instead of shared instance")
    public static let shared = CapabilityCalculatorCompat()

    /// Calculates capabilities for a media descriptor.
    ///
    /// - Parameters:
    ///   - descriptor: The media descriptor.
    ///   - backend: The probe backend identifier.
    ///   - analysisState: Current analysis state from MediaStore.
    ///   - timecode: Optional timecode extraction result for timecode capabilities.
    /// - Returns: Calculated capabilities.
    public static func calculate(
        for descriptor: MediaDescriptor,
        backend: String,
        analysisState: AnalysisState? = nil,
        timecode: TimecodeExtractionResult? = nil
    ) -> Capability {
        var caps = Capability()

        // Backend capabilities
        if backend == "AVFoundation" {
            caps.insert(.avFoundationBacked)
        }

        // Playback capabilities based on tracks
        if descriptor.hasVideo {
            caps.insert(.videoPlayback)
            caps.insert(.randomFrameAccess)
            caps.insert(.frameExtraction)
            caps.insert(.thumbnailGeneratable)

            // Check for frame-accurate seeking support
            if descriptor.keyframeHint == .allKeyframes {
                caps.insert(.frameAccurateSeeking)
            } else if descriptor.keyframeHint == .hasKeyframes {
                caps.insert(.keyframeIndexGeneratable)
            }

            // Check for reverse playback support (codec dependent)
            if let codec = descriptor.primaryVideoTrack?.codec.fourCC {
                if isReversePlaybackSupported(codec: codec) {
                    caps.insert(.reversePlayback)
                }
            }

            // Variable speed is generally available for video
            caps.insert(.variableSpeed)
        }

        if descriptor.hasAudio {
            caps.insert(.audioPlayback)
            caps.insert(.audioExtraction)
            caps.insert(.waveformGeneratable)
            caps.insert(.peakGeneratable)
        }

        // Composability
        caps.insert(.composable)

        // Color capabilities
        if let videoTrack = descriptor.primaryVideoTrack {
            if videoTrack.colorInfo.primaries != nil {
                caps.insert(.colorProfileInspection)
            }
            if videoTrack.colorInfo.isHDR {
                caps.insert(.hdrMetadata)
                caps.insert(.hdrTonemapping)
            }
        }

        // Analysis state capabilities
        if let state = analysisState {
            if state.waveform != nil {
                caps.insert(.waveformAvailable)
            }
            if state.peak != nil {
                caps.insert(.peakAvailable)
            }
            if state.keyframeIndex != nil {
                caps.insert(.keyframeIndexAvailable)
                caps.insert(.frameAccurateSeeking)
            }
            if state.thumbnailIndex != nil {
                caps.insert(.thumbnailIndexAvailable)
            }
        }

        // Timecode capabilities
        if let tc = timecode {
            switch tc.sourceKind {
            case "tmcd", "metadata":
                // Explicit timecode from embedded source
                caps.insert(.timecodeAvailable)
            case "inferred":
                // Inferred/estimated timecode
                caps.insert(.timecodeInferable)
            default:
                // Unknown source kind - treat as inferable
                caps.insert(.timecodeInferable)
            }
        }

        return caps
    }

    private static func isReversePlaybackSupported(codec: String) -> Bool {
        // Use centralized CodecRegistry for intra-frame codec detection
        CodecRegistry.supportsReversePlayback(codec.trimmingCharacters(in: .whitespaces))
    }
}

/// Compatibility wrapper for deprecated `CapabilityCalculator.shared` usage.
/// - Note: Migrate to static methods on `CapabilityCalculator` enum.
public struct CapabilityCalculatorCompat: Sendable {
    public func calculate(
        for descriptor: MediaDescriptor,
        backend: String,
        analysisState: AnalysisState? = nil,
        timecode: TimecodeExtractionResult? = nil
    ) -> Capability {
        CapabilityCalculator.calculate(
            for: descriptor,
            backend: backend,
            analysisState: analysisState,
            timecode: timecode
        )
    }
}

// MARK: - Analysis Data Types
//
// Analysis data types are defined in separate files under Core/AnalysisData/:
// - AnalysisState.swift: Aggregate state for all analysis data
// - WaveformData.swift: Audio waveform visualization data
// - PeakData.swift: Audio peak level data
// - KeyframeIndex.swift: Video keyframe position index
// - ThumbnailIndex.swift: Preview thumbnail index
