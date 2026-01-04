//
//  MediaDescriptor.swift
//  CYBMediaHolder
//
//  Immutable description of a media file's intrinsic properties.
//  This is the "facts" about the media that never change.
//

import Foundation
import CoreMedia
import UniformTypeIdentifiers

/// Type of media content.
public enum MediaType: String, Codable, Sendable, CaseIterable {
    /// Video content (may include audio).
    case video

    /// Audio-only content.
    case audio

    /// Still image.
    case image

    /// Image sequence (future).
    case imageSequence

    /// Unknown or unsupported type.
    case unknown
}

/// Container format information.
public struct ContainerInfo: Codable, Sendable, Hashable {

    /// Container format name (e.g., "QuickTime", "MPEG-4", "MXF").
    public let format: String

    /// File extension (e.g., "mov", "mp4", "mxf").
    public let fileExtension: String

    /// UTType identifier if available.
    public let uniformTypeIdentifier: String?

    /// Whether the container supports streaming.
    public let supportsStreaming: Bool

    /// Creates container info with all properties.
    public init(
        format: String,
        fileExtension: String,
        uniformTypeIdentifier: String? = nil,
        supportsStreaming: Bool = false
    ) {
        self.format = format
        self.fileExtension = fileExtension
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.supportsStreaming = supportsStreaming
    }
}

/// Keyframe accessibility hint.
///
/// Indicates the level of random access support.
public enum KeyframeHint: String, Codable, Sendable {
    /// Keyframe information not yet analyzed.
    case unknown

    /// Container has keyframes, seek should be fast.
    case hasKeyframes

    /// All frames are keyframes (e.g., ProRes, image sequence).
    case allKeyframes

    /// Keyframe index needs to be built for efficient seeking.
    case needsIndex

    /// No keyframes available (rare, streaming only).
    case noKeyframes
}

/// Immutable descriptor of a media file's intrinsic properties.
///
/// `MediaDescriptor` contains all the "facts" about a media file that
/// are determined at probe time and never change:
/// - Container format
/// - Duration and timebase
/// - Track information (video, audio)
/// - Color space and HDR metadata
///
/// ## Design Notes
/// - All properties are immutable (`let`)
/// - Created by `MediaProbe` implementations
/// - Backend-agnostic (works with AVFoundation, FFmpeg, etc.)
///
/// ## Future Extensions
/// - Subtitle track descriptors
/// - Chapter information
/// - Embedded metadata (XMP, EXIF)
public struct MediaDescriptor: Codable, Sendable {

    /// Type of media content.
    public let mediaType: MediaType

    /// Container format information.
    public let container: ContainerInfo

    /// Total duration of the media.
    public let duration: CMTime

    /// Duration in seconds (convenience).
    public var durationSeconds: Double {
        duration.seconds
    }

    /// Native timebase of the media.
    public let timebase: CMTimeScale

    /// Video track descriptors (may be empty for audio-only).
    public let videoTracks: [VideoTrackDescriptor]

    /// Audio track descriptors (may be empty for silent video).
    public let audioTracks: [AudioTrackDescriptor]

    /// Keyframe accessibility hint.
    public let keyframeHint: KeyframeHint

    /// File size in bytes (if known).
    public let fileSize: UInt64?

    /// File creation date (if available).
    public let creationDate: Date?

    /// File modification date (if available).
    public let modificationDate: Date?

    /// Original file name.
    public let fileName: String?

    /// Backend that created this descriptor.
    public let probeBackend: String

    /// Timestamp when this descriptor was created.
    public let probedAt: Date

    /// Creates a media descriptor with all properties.
    public init(
        mediaType: MediaType,
        container: ContainerInfo,
        duration: CMTime,
        timebase: CMTimeScale,
        videoTracks: [VideoTrackDescriptor],
        audioTracks: [AudioTrackDescriptor],
        keyframeHint: KeyframeHint = .unknown,
        fileSize: UInt64? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        fileName: String? = nil,
        probeBackend: String
    ) {
        self.mediaType = mediaType
        self.container = container
        self.duration = duration
        self.timebase = timebase
        self.videoTracks = videoTracks
        self.audioTracks = audioTracks
        self.keyframeHint = keyframeHint
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.fileName = fileName
        self.probeBackend = probeBackend
        self.probedAt = Date()
    }

    // MARK: - Convenience Properties

    /// Whether this media contains video.
    public var hasVideo: Bool {
        !videoTracks.isEmpty
    }

    /// Whether this media contains audio.
    public var hasAudio: Bool {
        !audioTracks.isEmpty
    }

    /// Primary video track (first track, if any).
    public var primaryVideoTrack: VideoTrackDescriptor? {
        videoTracks.first
    }

    /// Primary audio track (first track, if any).
    public var primaryAudioTrack: AudioTrackDescriptor? {
        audioTracks.first
    }

    /// Video dimensions of primary track.
    public var videoSize: CGSize? {
        primaryVideoTrack?.size
    }

    /// Frame rate of primary video track.
    public var frameRate: Float? {
        primaryVideoTrack?.nominalFrameRate
    }

    /// Whether any video track is HDR.
    public var isHDR: Bool {
        videoTracks.contains { $0.isHDR }
    }

    /// Total track count.
    public var totalTrackCount: Int {
        videoTracks.count + audioTracks.count
    }

    /// Estimated total frame count of primary video track.
    public var estimatedFrameCount: Int? {
        primaryVideoTrack?.estimatedFrameCount
    }
}

// MARK: - CustomStringConvertible

extension MediaDescriptor: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        parts.append("\(mediaType) - \(container.format)")

        if let size = videoSize {
            parts.append("\(Int(size.width))x\(Int(size.height))")
        }

        if let fps = frameRate {
            parts.append(String(format: "%.2f fps", fps))
        }

        parts.append(String(format: "%.2f sec", durationSeconds))

        if isHDR {
            parts.append("HDR")
        }

        return parts.joined(separator: ", ")
    }
}
