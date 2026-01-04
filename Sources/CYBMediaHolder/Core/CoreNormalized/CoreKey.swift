//
//  CoreKey.swift
//  CYBMediaHolder
//
//  Vendor-independent normalization keys for media metadata.
//  Defines the stable `core/*` namespace for cross-backend interoperability.
//

import Foundation

/// Enumeration of `core/*` normalization keys.
///
/// `CoreKey` defines a stable, vendor-independent namespace for media metadata.
/// These keys are designed to:
/// - Be implementation-agnostic (works with AVFoundation, FFmpeg, Sony, etc.)
/// - Provide consistent naming across different probe backends
/// - Support future extension without breaking existing code
///
/// ## Namespace Design
/// - `core/asset.*`: Identity and location
/// - `core/container.*`: Container-level properties
/// - `core/video.*`: Video stream properties
/// - `core/audio.*`: Audio stream properties
/// - `core/timecode.*`: Timecode information (future)
/// - `core/color.*`: Color space and HDR metadata
///
/// ## Future Extensions
/// - Timecode extraction from embedded metadata
/// - GOP/keyframe analysis results
/// - Plugin-specific metadata via `ext/*` namespace
public enum CoreKey: String, CaseIterable, Sendable, Hashable {

    // MARK: - Asset Identity

    /// Unique identifier for the asset (UUID string).
    case assetId = "core/asset.id"

    /// URI or path to the asset.
    case assetURI = "core/asset.uri"

    /// Content fingerprint (hash) for deduplication.
    case assetFingerprint = "core/asset.fingerprint"

    // MARK: - Container Properties

    /// Container format name (e.g., "QuickTime", "MXF").
    case containerFormat = "core/container.format"

    /// Total duration in seconds.
    case containerDurationSeconds = "core/container.duration_s"

    /// File size in bytes.
    case containerSizeBytes = "core/container.size_bytes"

    /// Total number of tracks (video + audio + other).
    case containerTrackCount = "core/container.track_count"

    // MARK: - Video Properties

    /// Video codec identifier (e.g., "avc1", "hvc1", "ap4h").
    case videoCodec = "core/video.codec"

    /// Video width in pixels.
    case videoWidth = "core/video.width"

    /// Video height in pixels.
    case videoHeight = "core/video.height"

    /// Frame rate as floating point.
    case videoFPS = "core/video.fps"

    /// Scan type ("progressive", "interlaced", "unknown").
    case videoScan = "core/video.scan"

    /// Bit depth per component (8, 10, 12, etc.).
    case videoBitDepth = "core/video.bit_depth"

    /// Chroma subsampling (e.g., "4:2:0", "4:2:2", "4:4:4").
    case videoChroma = "core/video.chroma"

    // MARK: - Audio Properties

    /// Number of audio tracks.
    case audioTrackCount = "core/audio.track_count"

    /// Number of audio channels (primary track).
    case audioChannels = "core/audio.channels"

    /// Sample rate in Hz.
    case audioSampleRateHz = "core/audio.sample_rate_hz"

    /// Audio bit depth (primary track).
    case audioBitDepth = "core/audio.bit_depth"

    // MARK: - Timecode Properties (Future)

    /// Start timecode as string (e.g., "01:00:00:00").
    case timecodeStart = "core/timecode.start"

    /// Timecode rate (e.g., 24, 25, 29.97).
    case timecodeRate = "core/timecode.rate"

    /// Whether timecode is drop-frame.
    case timecodeDropFrame = "core/timecode.drop_frame"

    /// Source kind of timecode ("embedded", "filename", "metadata", "none").
    case timecodeSourceKind = "core/timecode.source_kind"

    /// Specific source of timecode (e.g., "tmcd track", "QuickTime metadata").
    case timecodeSource = "core/timecode.source"

    // MARK: - Color Properties

    /// Color primaries (e.g., "bt709", "bt2020", "p3").
    case colorPrimaries = "core/color.primaries"

    /// Transfer function (e.g., "bt709", "pq", "hlg").
    case colorTransfer = "core/color.transfer"

    /// Matrix coefficients (e.g., "bt709", "bt2020_ncl").
    case colorMatrix = "core/color.matrix"

    /// Color range ("full", "limited").
    case colorRange = "core/color.range"

    /// Whether content is HDR.
    case colorHDR = "core/color.hdr"
}

// MARK: - Convenience Properties

extension CoreKey {

    /// The namespace of this key (e.g., "core/asset" → "asset").
    public var namespace: String {
        let parts = rawValue.components(separatedBy: "/")
        guard parts.count >= 2 else { return rawValue }
        return parts[1].components(separatedBy: ".").first ?? parts[1]
    }

    /// The property name within the namespace (e.g., "core/asset.id" → "id").
    public var propertyName: String {
        let parts = rawValue.components(separatedBy: ".")
        return parts.last ?? rawValue
    }

    /// All keys in the asset namespace.
    public static var assetKeys: [CoreKey] {
        [.assetId, .assetURI, .assetFingerprint]
    }

    /// All keys in the container namespace.
    public static var containerKeys: [CoreKey] {
        [.containerFormat, .containerDurationSeconds, .containerSizeBytes, .containerTrackCount]
    }

    /// All keys in the video namespace.
    public static var videoKeys: [CoreKey] {
        [.videoCodec, .videoWidth, .videoHeight, .videoFPS, .videoScan, .videoBitDepth, .videoChroma]
    }

    /// All keys in the audio namespace.
    public static var audioKeys: [CoreKey] {
        [.audioTrackCount, .audioChannels, .audioSampleRateHz, .audioBitDepth]
    }

    /// All keys in the timecode namespace.
    public static var timecodeKeys: [CoreKey] {
        [.timecodeStart, .timecodeRate, .timecodeDropFrame, .timecodeSourceKind, .timecodeSource]
    }

    /// All keys in the color namespace.
    public static var colorKeys: [CoreKey] {
        [.colorPrimaries, .colorTransfer, .colorMatrix, .colorRange, .colorHDR]
    }
}

// MARK: - CustomStringConvertible

extension CoreKey: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}
