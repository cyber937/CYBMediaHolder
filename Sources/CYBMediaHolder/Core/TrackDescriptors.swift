//
//  TrackDescriptors.swift
//  CYBMediaHolder
//
//  Immutable descriptors for video and audio tracks.
//  Contains all static properties of a track.
//

import Foundation
import CoreMedia
import AVFoundation

/// Codec information extracted from format description.
public struct CodecInfo: Codable, Sendable, Hashable {

    /// Four-character code as string (e.g., "avc1", "hvc1", "aac ").
    public let fourCC: String

    /// Human-readable codec name.
    public let displayName: String

    /// Codec profile (e.g., "High", "Main 10").
    public let profile: String?

    /// Codec level (e.g., "4.1", "5.1").
    public let level: String?

    /// Creates codec info with all properties.
    public init(
        fourCC: String,
        displayName: String,
        profile: String? = nil,
        level: String? = nil
    ) {
        self.fourCC = fourCC
        self.displayName = displayName
        self.profile = profile
        self.level = level
    }

    /// Creates codec info from a FourCharCode.
    ///
    /// Uses `CodecRegistry` for display name lookup to ensure consistency
    /// across the codebase.
    public init(from fourCC: FourCharCode) {
        let fourCCString = fourCC.asString
        self.fourCC = fourCCString
        // Delegate to CodecRegistry for consistent display names
        self.displayName = CodecRegistry.displayName(for: fourCCString.trimmingCharacters(in: .whitespaces))
        self.profile = nil
        self.level = nil
    }
}

/// Immutable descriptor for a video track.
///
/// Contains all static properties of a video track that don't change
/// during playback.
///
/// ## Design Notes
/// - All properties are immutable
/// - VFR (variable frame rate) detection included
/// - Color info for accurate rendering pipeline setup
///
/// ## Future Extensions
/// - HDR metadata (mastering display, content light level)
/// - Stereo 3D information
/// - Rotation/orientation metadata
public struct VideoTrackDescriptor: Codable, Sendable, Identifiable {

    /// Unique identifier for this track within the media.
    public let id: Int

    /// Track index in the container (0-based).
    public let trackIndex: Int

    /// Codec information.
    public let codec: CodecInfo

    /// Video dimensions in pixels.
    public let size: CGSize

    /// Display aspect ratio (may differ from size due to anamorphic).
    public let displayAspectRatio: CGFloat?

    /// Nominal frame rate (may not be exact for VFR content).
    public let nominalFrameRate: Float

    /// Minimum frame duration (for frame-accurate seeking).
    public let minFrameDuration: CMTime

    /// Whether the track has variable frame rate.
    public let isVFR: Bool

    /// Color space and HDR information.
    public let colorInfo: ColorInfo

    /// Time range of this track.
    public let timeRange: CMTimeRange

    /// Native timescale of the track.
    public let timescale: CMTimeScale

    /// Average bitrate in bits per second (if available).
    public let averageBitRate: Float?

    /// Creates a video track descriptor with all properties.
    public init(
        id: Int,
        trackIndex: Int,
        codec: CodecInfo,
        size: CGSize,
        displayAspectRatio: CGFloat? = nil,
        nominalFrameRate: Float,
        minFrameDuration: CMTime,
        isVFR: Bool = false,
        colorInfo: ColorInfo,
        timeRange: CMTimeRange,
        timescale: CMTimeScale,
        averageBitRate: Float? = nil
    ) {
        self.id = id
        self.trackIndex = trackIndex
        self.codec = codec
        self.size = size
        self.displayAspectRatio = displayAspectRatio
        self.nominalFrameRate = nominalFrameRate
        self.minFrameDuration = minFrameDuration
        self.isVFR = isVFR
        self.colorInfo = colorInfo
        self.timeRange = timeRange
        self.timescale = timescale
        self.averageBitRate = averageBitRate
    }

    /// Calculated total frame count (approximate for VFR).
    public var estimatedFrameCount: Int {
        Int((timeRange.duration.seconds * Double(nominalFrameRate)).rounded())
    }

    /// Whether this is HDR content.
    public var isHDR: Bool {
        colorInfo.isHDR
    }
}

// MARK: - VideoTrackDescriptor Hashable

extension VideoTrackDescriptor: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(trackIndex)
        hasher.combine(codec)
        hasher.combine(size.width)
        hasher.combine(size.height)
        hasher.combine(displayAspectRatio)
        hasher.combine(nominalFrameRate)
        hasher.combine(isVFR)
        hasher.combine(colorInfo)
        hasher.combine(timescale)
        hasher.combine(averageBitRate)
    }

    public static func == (lhs: VideoTrackDescriptor, rhs: VideoTrackDescriptor) -> Bool {
        lhs.id == rhs.id &&
        lhs.trackIndex == rhs.trackIndex &&
        lhs.codec == rhs.codec &&
        lhs.size.width == rhs.size.width &&
        lhs.size.height == rhs.size.height &&
        lhs.displayAspectRatio == rhs.displayAspectRatio &&
        lhs.nominalFrameRate == rhs.nominalFrameRate &&
        lhs.isVFR == rhs.isVFR &&
        lhs.colorInfo == rhs.colorInfo &&
        lhs.timescale == rhs.timescale &&
        lhs.averageBitRate == rhs.averageBitRate
    }
}

/// Immutable descriptor for an audio track.
///
/// Contains all static properties of an audio track.
///
/// ## Design Notes
/// - Channel layout for proper spatial audio rendering
/// - Sample rate and bit depth for quality assessment
///
/// ## Future Extensions
/// - Spatial audio metadata (Atmos, etc.)
/// - Language and accessibility flags
public struct AudioTrackDescriptor: Codable, Sendable, Hashable, Identifiable {

    /// Unique identifier for this track within the media.
    public let id: Int

    /// Track index in the container (0-based).
    public let trackIndex: Int

    /// Codec information.
    public let codec: CodecInfo

    /// Sample rate in Hz.
    public let sampleRate: Double

    /// Number of channels.
    public let channelCount: Int

    /// Channel layout description (e.g., "stereo", "5.1", "7.1.4").
    public let channelLayout: String?

    /// Bits per sample (for PCM) or nominal bit depth.
    public let bitsPerSample: Int?

    /// Average bitrate in bits per second.
    public let averageBitRate: Float?

    /// Time range of this track.
    public let timeRange: CMTimeRange

    /// Language code (ISO 639-2/T, e.g., "eng", "jpn").
    public let languageCode: String?

    /// Creates an audio track descriptor with all properties.
    public init(
        id: Int,
        trackIndex: Int,
        codec: CodecInfo,
        sampleRate: Double,
        channelCount: Int,
        channelLayout: String? = nil,
        bitsPerSample: Int? = nil,
        averageBitRate: Float? = nil,
        timeRange: CMTimeRange,
        languageCode: String? = nil
    ) {
        self.id = id
        self.trackIndex = trackIndex
        self.codec = codec
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.channelLayout = channelLayout
        self.bitsPerSample = bitsPerSample
        self.averageBitRate = averageBitRate
        self.timeRange = timeRange
        self.languageCode = languageCode
    }

    /// Human-readable channel layout.
    public var channelLayoutDescription: String {
        if let layout = channelLayout {
            return layout
        }
        switch channelCount {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channelCount) channels"
        }
    }
}

// MARK: - FourCharCode Extension

extension FourCharCode {
    /// Converts FourCharCode to a String.
    var asString: String {
        let bytes: [UInt8] = [
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - CMTime Codable

#if swift(>=6.0)
extension CMTime: @retroactive Encodable {}
extension CMTime: @retroactive Decodable {}
#else
extension CMTime: Encodable {}
extension CMTime: Decodable {}
#endif

extension CMTime {
    enum CodingKeys: String, CodingKey {
        case value, timescale, flags, epoch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(CMTimeValue.self, forKey: .value)
        let timescale = try container.decode(CMTimeScale.self, forKey: .timescale)
        let flags = try container.decode(UInt32.self, forKey: .flags)
        let epoch = try container.decode(CMTimeEpoch.self, forKey: .epoch)
        self = CMTime(value: value, timescale: timescale, flags: CMTimeFlags(rawValue: flags), epoch: epoch)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(timescale, forKey: .timescale)
        try container.encode(flags.rawValue, forKey: .flags)
        try container.encode(epoch, forKey: .epoch)
    }
}

// MARK: - CMTimeRange Codable

#if swift(>=6.0)
extension CMTimeRange: @retroactive Encodable {}
extension CMTimeRange: @retroactive Decodable {}
#else
extension CMTimeRange: Encodable {}
extension CMTimeRange: Decodable {}
#endif

extension CMTimeRange {
    enum CodingKeys: String, CodingKey {
        case start, duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(CMTime.self, forKey: .start)
        let duration = try container.decode(CMTime.self, forKey: .duration)
        self = CMTimeRange(start: start, duration: duration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(duration, forKey: .duration)
    }
}
