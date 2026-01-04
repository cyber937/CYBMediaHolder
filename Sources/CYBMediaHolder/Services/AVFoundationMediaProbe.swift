//
//  AVFoundationMediaProbe.swift
//  CYBMediaHolder
//
//  AVFoundation-based implementation of MediaProbe.
//  Extracts media descriptors using AVAsset.
//

import Foundation
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers
import os.log

/// Logger for AVFoundation probe operations.
private let logger = Logger(subsystem: "com.cyberseeds.CYBMediaHolder", category: "AVFoundationProbe")

// MARK: - Extended Probe Result

/// Extended probe result containing descriptor and timecode information.
///
/// This type combines the immutable `MediaDescriptor` with extracted timecode data,
/// providing a complete picture of the media's metadata including timing information.
public struct ExtendedProbeResult: Sendable {

    /// The media descriptor containing core metadata.
    public let descriptor: MediaDescriptor

    /// Extracted timecode information.
    public let timecode: TimecodeExtractionResult

    /// Creates an extended probe result.
    public init(descriptor: MediaDescriptor, timecode: TimecodeExtractionResult) {
        self.descriptor = descriptor
        self.timecode = timecode
    }
}

// MARK: - Timecode Extraction Result

/// Result of timecode extraction from a media asset.
///
/// Contains all timecode-related metadata with provenance information.
/// Used internally by `AVFoundationMediaProbe` and stored in `CoreNormalizedStore`.
public struct TimecodeExtractionResult: Sendable, Equatable {

    /// Start timecode as string (e.g., "01:00:00:00").
    public let start: String

    /// Timecode rate (e.g., 24, 25, 29.97, 30).
    public let rate: Double

    /// Whether the timecode uses drop-frame format.
    public let dropFrame: Bool

    /// Source kind identifier for provenance.
    /// - "tmcd": Extracted from timecode track
    /// - "metadata": Extracted from timed metadata
    /// - "inferred": Estimated/default value
    public let sourceKind: String

    /// Detailed source description (e.g., "tmcd track 0", "QuickTime metadata").
    public let source: String

    /// Confidence score (0.0-1.0).
    /// - 0.95: tmcd track (highly reliable)
    /// - 0.8: timed metadata (reliable)
    /// - 0.3: inferred (best-effort estimate)
    public let confidence: Double

    /// Creates an inferred (default) timecode result.
    ///
    /// Used when no explicit timecode is found in the media.
    ///
    /// - Parameter frameRate: The video frame rate for timecode rate.
    /// - Returns: A TimecodeExtractionResult with default values.
    public static func inferred(frameRate: Double) -> TimecodeExtractionResult {
        TimecodeExtractionResult(
            start: "00:00:00:00",
            rate: frameRate > 0 ? frameRate : 30.0,
            dropFrame: false,
            sourceKind: "inferred",
            source: "default (no embedded timecode)",
            confidence: 0.3
        )
    }
}

/// AVFoundation-based media probe implementation.
///
/// Uses AVAsset to extract comprehensive media information including:
/// - Video track properties (codec, size, frame rate, color)
/// - Audio track properties (codec, channels, sample rate)
/// - Container format
/// - Duration and timing
///
/// ## Supported Formats
/// - QuickTime (.mov)
/// - MPEG-4 (.mp4, .m4v, .m4a)
/// - MPEG-2 TS (.ts)
/// - Common audio formats (.aac, .mp3, .wav, .aiff)
///
/// ## Limitations
/// - Some professional formats may have incomplete color metadata
/// - VFR detection is approximate
/// - Some codec profiles/levels not fully extracted
public struct AVFoundationMediaProbe: MediaProbe, Sendable {

    public let identifier = "AVFoundation"
    public let displayName = "AVFoundation"

    public let supportedExtensions: Set<String> = [
        // Video
        "mov", "mp4", "m4v", "3gp", "3g2",
        // Audio
        "m4a", "aac", "mp3", "wav", "aiff", "aif", "caf",
        // Transport stream
        "ts", "mts", "m2ts"
    ]

    public let supportedUTTypes: Set<String> = [
        "public.movie",
        "public.audio",
        "com.apple.quicktime-movie",
        "public.mpeg-4",
        "public.mpeg-4-audio"
    ]

    public init() {}

    // MARK: - Probing

    public func probe(locator: MediaLocator) async throws -> MediaDescriptor {
        let result = try await probeExtended(locator: locator)
        return result.descriptor
    }

    /// Probes a media file and returns extended result including timecode.
    ///
    /// This method extracts both the standard media descriptor and timecode information.
    /// Use this when you need timecode data in addition to standard metadata.
    ///
    /// - Parameter locator: The media locator.
    /// - Returns: Extended probe result with descriptor and timecode.
    /// - Throws: `MediaProbeError` if probing fails.
    public func probeExtended(locator: MediaLocator) async throws -> ExtendedProbeResult {
        // Resolve the locator to a URL
        let resolved: MediaLocator.ResolvedURL
        do {
            resolved = try await locator.resolve()
        } catch let error as MediaLocator.ResolutionError {
            throw MediaProbeError.locatorResolutionFailed(error)
        }

        defer {
            resolved.stopAccessing()
        }

        let url = resolved.url

        // Create AVAsset
        let asset = AVAsset(url: url)

        // Load essential properties
        let (isPlayable, isReadable, duration, tracks) = try await loadAssetProperties(asset)

        guard isPlayable || isReadable else {
            throw MediaProbeError.notPlayable(reason: "Asset is not playable or readable")
        }

        guard !tracks.isEmpty else {
            throw MediaProbeError.noTracksFound
        }

        // Extract file info
        let fileInfo = try extractFileInfo(from: url)

        // Separate video and audio tracks
        let videoTracks = tracks.filter { $0.mediaType == .video }
        let audioTracks = tracks.filter { $0.mediaType == .audio }

        // Build track descriptors
        let videoDescriptors = try await buildVideoTrackDescriptors(from: videoTracks)
        let audioDescriptors = try await buildAudioTrackDescriptors(from: audioTracks)

        // Determine media type
        let mediaType: MediaType
        if !videoDescriptors.isEmpty {
            mediaType = .video
        } else if !audioDescriptors.isEmpty {
            mediaType = .audio
        } else {
            mediaType = .unknown
        }

        // Determine keyframe hint
        let keyframeHint = determineKeyframeHint(from: videoDescriptors)

        // Determine timebase
        let timebase: CMTimeScale
        if let videoTrack = videoDescriptors.first {
            timebase = videoTrack.timescale
        } else if let audioTrack = audioDescriptors.first {
            timebase = CMTimeScale(audioTrack.sampleRate)
        } else {
            timebase = 600 // Default
        }

        // Build container info
        let container = buildContainerInfo(from: url, fileInfo: fileInfo)

        // Extract timecode
        let nominalFrameRate = videoDescriptors.first?.nominalFrameRate ?? 30.0
        let timecode = await extractTimecode(
            from: asset,
            tracks: tracks,
            nominalFrameRate: nominalFrameRate
        )

        let descriptor = MediaDescriptor(
            mediaType: mediaType,
            container: container,
            duration: duration,
            timebase: timebase,
            videoTracks: videoDescriptors,
            audioTracks: audioDescriptors,
            keyframeHint: keyframeHint,
            fileSize: fileInfo.size,
            creationDate: fileInfo.creationDate,
            modificationDate: fileInfo.modificationDate,
            fileName: url.lastPathComponent,
            probeBackend: identifier
        )

        return ExtendedProbeResult(descriptor: descriptor, timecode: timecode)
    }

    // MARK: - Asset Property Loading

    private func loadAssetProperties(_ asset: AVAsset) async throws -> (
        isPlayable: Bool,
        isReadable: Bool,
        duration: CMTime,
        tracks: [AVAssetTrack]
    ) {
        do {
            let (isPlayable, isReadable, duration, tracks) = try await asset.load(
                .isPlayable,
                .isReadable,
                .duration,
                .tracks
            )
            return (isPlayable, isReadable, duration, tracks)
        } catch {
            throw MediaProbeError.propertyLoadFailed(error)
        }
    }

    // MARK: - Video Track Processing

    private func buildVideoTrackDescriptors(
        from tracks: [AVAssetTrack]
    ) async throws -> [VideoTrackDescriptor] {
        var descriptors: [VideoTrackDescriptor] = []

        for (index, track) in tracks.enumerated() {
            do {
                let descriptor = try await buildVideoTrackDescriptor(
                    from: track,
                    index: index
                )
                descriptors.append(descriptor)
            } catch {
                // Log and continue with other tracks
                logger.warning("Failed to process video track \(index): \(error.localizedDescription)")
            }
        }

        return descriptors
    }

    private func buildVideoTrackDescriptor(
        from track: AVAssetTrack,
        index: Int
    ) async throws -> VideoTrackDescriptor {
        let (
            nominalFrameRate,
            minFrameDuration,
            naturalSize,
            timeRange,
            formatDescriptions
        ) = try await track.load(
            .nominalFrameRate,
            .minFrameDuration,
            .naturalSize,
            .timeRange,
            .formatDescriptions
        )

        // Extract codec info
        let codec: CodecInfo
        if let formatDesc = formatDescriptions.first {
            let fourCC = CMFormatDescriptionGetMediaSubType(formatDesc)
            codec = CodecInfo(from: fourCC)
        } else {
            codec = CodecInfo(fourCC: "????", displayName: "Unknown")
        }

        // Extract color info
        let colorInfo: ColorInfo
        if let formatDesc = formatDescriptions.first {
            colorInfo = ColorInfo(from: formatDesc)
        } else {
            colorInfo = ColorInfo()
        }

        // Estimate if VFR
        let isVFR = await estimateVFR(track: track, nominalFrameRate: nominalFrameRate)

        return VideoTrackDescriptor(
            id: index,
            trackIndex: index,
            codec: codec,
            size: naturalSize,
            displayAspectRatio: naturalSize.width / naturalSize.height,
            nominalFrameRate: nominalFrameRate,
            minFrameDuration: minFrameDuration,
            isVFR: isVFR,
            colorInfo: colorInfo,
            timeRange: timeRange,
            timescale: minFrameDuration.timescale,
            averageBitRate: nil
        )
    }

    private func estimateVFR(track: AVAssetTrack, nominalFrameRate: Float) async -> Bool {
        // Simple VFR detection: compare nominal and min frame rates
        // More accurate detection would require segment analysis
        do {
            let segments = try await track.load(.segments)
            if segments.count > 1 {
                // Multiple segments might indicate VFR or edited content
                return true
            }
        } catch {
            // Ignore segment loading errors
        }
        return false
    }

    // MARK: - Audio Track Processing

    private func buildAudioTrackDescriptors(
        from tracks: [AVAssetTrack]
    ) async throws -> [AudioTrackDescriptor] {
        var descriptors: [AudioTrackDescriptor] = []

        for (index, track) in tracks.enumerated() {
            do {
                let descriptor = try await buildAudioTrackDescriptor(
                    from: track,
                    index: index
                )
                descriptors.append(descriptor)
            } catch {
                logger.warning("Failed to process audio track \(index): \(error.localizedDescription)")
            }
        }

        return descriptors
    }

    private func buildAudioTrackDescriptor(
        from track: AVAssetTrack,
        index: Int
    ) async throws -> AudioTrackDescriptor {
        let (timeRange, formatDescriptions) = try await track.load(
            .timeRange,
            .formatDescriptions
        )

        // Extract audio properties
        var sampleRate: Double = 48000
        var channelCount: Int = 2
        var codec = CodecInfo(fourCC: "????", displayName: "Unknown")

        if let formatDesc = formatDescriptions.first {
            let fourCC = CMFormatDescriptionGetMediaSubType(formatDesc)
            codec = CodecInfo(from: fourCC)

            // Get audio stream basic description
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                sampleRate = asbd.pointee.mSampleRate
                channelCount = Int(asbd.pointee.mChannelsPerFrame)
            }
        }

        // Try to get language
        let languageCode = try? await track.load(.languageCode)

        return AudioTrackDescriptor(
            id: index,
            trackIndex: index,
            codec: codec,
            sampleRate: sampleRate,
            channelCount: channelCount,
            channelLayout: nil,
            bitsPerSample: nil,
            averageBitRate: nil,
            timeRange: timeRange,
            languageCode: languageCode
        )
    }

    // MARK: - File Info

    private struct FileInfo {
        let size: UInt64?
        let creationDate: Date?
        let modificationDate: Date?
        let contentType: UTType?
    }

    private func extractFileInfo(from url: URL) throws -> FileInfo {
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentTypeKey
        ])

        return FileInfo(
            size: resourceValues.fileSize.map { UInt64($0) },
            creationDate: resourceValues.creationDate,
            modificationDate: resourceValues.contentModificationDate,
            contentType: resourceValues.contentType
        )
    }

    // MARK: - Container Info

    private func buildContainerInfo(from url: URL, fileInfo: FileInfo) -> ContainerInfo {
        let ext = url.pathExtension.lowercased()

        let format: String
        let supportsStreaming: Bool

        switch ext {
        case "mov":
            format = "QuickTime"
            supportsStreaming = true
        case "mp4", "m4v":
            format = "MPEG-4"
            supportsStreaming = true
        case "m4a":
            format = "MPEG-4 Audio"
            supportsStreaming = true
        case "ts", "mts", "m2ts":
            format = "MPEG-2 Transport Stream"
            supportsStreaming = true
        case "wav":
            format = "WAVE"
            supportsStreaming = false
        case "aiff", "aif":
            format = "AIFF"
            supportsStreaming = false
        case "mp3":
            format = "MP3"
            supportsStreaming = true
        default:
            format = "Unknown"
            supportsStreaming = false
        }

        return ContainerInfo(
            format: format,
            fileExtension: ext,
            uniformTypeIdentifier: fileInfo.contentType?.identifier,
            supportsStreaming: supportsStreaming
        )
    }

    // MARK: - Keyframe Hint

    private func determineKeyframeHint(
        from videoTracks: [VideoTrackDescriptor]
    ) -> KeyframeHint {
        guard let primaryTrack = videoTracks.first else {
            return .unknown
        }

        let codec = primaryTrack.codec.fourCC.trimmingCharacters(in: .whitespaces)

        // Use centralized CodecRegistry for intra-frame codec detection
        if CodecRegistry.isIntraOnly(codec) {
            return .allKeyframes
        }

        // Inter-frame codecs (has keyframes, may need index)
        let interCodecs: Set<String> = ["avc1", "avc3", "hvc1", "hev1", "av01", "vp09"]
        if interCodecs.contains(codec) {
            return .hasKeyframes
        }

        return .unknown
    }

    // MARK: - Timecode Extraction

    /// Extracts timecode information from an AVAsset.
    ///
    /// Extraction priority:
    /// 1. Timecode track (tmcd) - highest confidence (0.95)
    /// 2. Timed metadata - medium confidence (0.8)
    /// 3. Inferred from frame rate - lowest confidence (0.3)
    ///
    /// - Parameters:
    ///   - asset: The AVAsset to extract timecode from.
    ///   - tracks: All tracks in the asset.
    ///   - nominalFrameRate: The nominal frame rate from video track.
    /// - Returns: TimecodeExtractionResult with timecode data and provenance.
    public func extractTimecode(
        from asset: AVAsset,
        tracks: [AVAssetTrack],
        nominalFrameRate: Float
    ) async -> TimecodeExtractionResult {
        // Priority 1: Try to extract from timecode track (tmcd)
        if let result = await extractFromTimecodeTrack(asset: asset, tracks: tracks) {
            logger.debug("Extracted timecode from tmcd track: \(result.start)")
            return result
        }

        // Priority 2: Try to extract from timed metadata
        if let result = await extractFromTimedMetadata(asset: asset) {
            logger.debug("Extracted timecode from metadata: \(result.start)")
            return result
        }

        // Priority 3: Infer from frame rate (fallback)
        let frameRate = Double(nominalFrameRate)
        logger.debug("No embedded timecode found, using inferred: 00:00:00:00 @ \(frameRate) fps")
        return .inferred(frameRate: frameRate)
    }

    /// Extracts timecode from a timecode track (tmcd).
    ///
    /// QuickTime and some other formats embed timecode in a dedicated track.
    private func extractFromTimecodeTrack(
        asset: AVAsset,
        tracks: [AVAssetTrack]
    ) async -> TimecodeExtractionResult? {
        // Find timecode tracks
        let timecodeTracks = tracks.filter { $0.mediaType == .timecode }

        guard let timecodeTrack = timecodeTracks.first else {
            return nil
        }

        do {
            // Load format descriptions from the timecode track
            let formatDescriptions = try await timecodeTrack.load(.formatDescriptions)

            guard let formatDesc = formatDescriptions.first else {
                return nil
            }

            // Extract timecode format info
            let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)

            // Check if this is a timecode format (tmcd = 0x746D6364)
            guard mediaSubType == kCMTimeCodeFormatType_TimeCode32 ||
                  mediaSubType == kCMTimeCodeFormatType_TimeCode64 ||
                  mediaSubType == kCMTimeCodeFormatType_Counter32 ||
                  mediaSubType == kCMTimeCodeFormatType_Counter64 else {
                return nil
            }

            // Get timecode flags and frame rate from format description
            var frameRate: Double = 30.0
            var dropFrame = false

            // Extract frame duration to calculate frame rate
            if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] {
                // Try to get frame duration using the raw key string
                // The key is "FrameDuration" in the extensions dictionary
                if let frameDuration = extensions["FrameDuration"] as? [String: Any],
                   let value = frameDuration["value"] as? Int64,
                   let timescale = frameDuration["timescale"] as? Int32,
                   timescale > 0 && value > 0 {
                    frameRate = Double(timescale) / Double(value)
                }

                // Check for drop frame flag in timecode flags
                if let tcFlags = extensions["TimeCodeFlags"] as? UInt32 {
                    // kCMTimeCodeFlag_DropFrame = 1 << 0
                    dropFrame = (tcFlags & 0x01) != 0
                }
            }

            // Try to read the first timecode sample
            let timecodeString = await readFirstTimecodeSample(
                from: timecodeTrack,
                formatDescription: formatDesc,
                frameRate: frameRate,
                dropFrame: dropFrame
            )

            return TimecodeExtractionResult(
                start: timecodeString ?? "00:00:00:00",
                rate: frameRate,
                dropFrame: dropFrame,
                sourceKind: "tmcd",
                source: "timecode track \(timecodeTrack.trackID)",
                confidence: 0.95
            )

        } catch {
            logger.warning("Failed to load timecode track format: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reads the first timecode sample from a timecode track.
    private func readFirstTimecodeSample(
        from track: AVAssetTrack,
        formatDescription: CMFormatDescription,
        frameRate: Double,
        dropFrame: Bool
    ) async -> String? {
        do {
            // Create asset reader for the timecode track
            guard let asset = track.asset else { return nil }

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else { return nil }
            reader.add(output)

            guard reader.startReading() else { return nil }

            defer {
                reader.cancelReading()
            }

            // Read first sample buffer
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                return nil
            }

            // Get the timecode data
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?

            let status = CMBlockBufferGetDataPointer(
                dataBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )

            guard status == kCMBlockBufferNoErr,
                  let pointer = dataPointer,
                  length >= 4 else {
                return nil
            }

            // Read frame number (big-endian 32-bit or 64-bit integer)
            let frameNumber: Int64
            if length >= 8 {
                // 64-bit timecode
                frameNumber = pointer.withMemoryRebound(to: Int64.self, capacity: 1) {
                    Int64(bigEndian: $0.pointee)
                }
            } else {
                // 32-bit timecode
                frameNumber = Int64(pointer.withMemoryRebound(to: Int32.self, capacity: 1) {
                    Int32(bigEndian: $0.pointee)
                })
            }

            // Convert frame number to timecode string
            return frameNumberToTimecode(
                frameNumber: frameNumber,
                frameRate: frameRate,
                dropFrame: dropFrame
            )

        } catch {
            logger.warning("Failed to read timecode sample: \(error.localizedDescription)")
            return nil
        }
    }

    /// Converts a frame number to a timecode string.
    ///
    /// - Note: This is a simplified conversion. Drop-frame calculation
    ///   is not fully implemented in v1 (always treats as non-drop-frame).
    private func frameNumberToTimecode(
        frameNumber: Int64,
        frameRate: Double,
        dropFrame: Bool
    ) -> String {
        // For v1, we use simple non-drop-frame calculation
        // Full drop-frame support is planned for v2
        let fps = Int(frameRate.rounded())
        guard fps > 0 else { return "00:00:00:00" }

        var frames = frameNumber
        if frames < 0 { frames = 0 }

        let ff = Int(frames % Int64(fps))
        frames /= Int64(fps)

        let ss = Int(frames % 60)
        frames /= 60

        let mm = Int(frames % 60)
        frames /= 60

        let hh = Int(frames % 24)

        // Use semicolon separator for drop-frame indication
        let separator = dropFrame ? ";" : ":"

        return String(format: "%02d:%02d:%02d%@%02d", hh, mm, ss, separator, ff)
    }

    /// Extracts timecode from timed metadata.
    ///
    /// Some formats store timecode in metadata rather than a dedicated track.
    private func extractFromTimedMetadata(
        asset: AVAsset
    ) async -> TimecodeExtractionResult? {
        do {
            // Load common metadata
            let metadata = try await asset.load(.commonMetadata)

            // Look for timecode in common metadata keys
            for item in metadata {
                guard let key = item.commonKey?.rawValue else { continue }

                // Check for known timecode metadata keys
                if key.lowercased().contains("timecode") ||
                   key.lowercased().contains("starttime") {
                    if let value = try? await item.load(.stringValue),
                       isValidTimecodeString(value) {
                        return TimecodeExtractionResult(
                            start: normalizeTimecodeString(value),
                            rate: 30.0, // Default, metadata often doesn't include rate
                            dropFrame: value.contains(";"),
                            sourceKind: "metadata",
                            source: "common metadata: \(key)",
                            confidence: 0.8
                        )
                    }
                }
            }

            // Try QuickTime-specific metadata
            let formats = try await asset.load(.availableMetadataFormats)

            for format in formats {
                let formatMetadata = try await asset.loadMetadata(for: format)

                for item in formatMetadata {
                    if let identifier = item.identifier?.rawValue,
                       identifier.lowercased().contains("timecode") {
                        if let value = try? await item.load(.stringValue),
                           isValidTimecodeString(value) {
                            return TimecodeExtractionResult(
                                start: normalizeTimecodeString(value),
                                rate: 30.0,
                                dropFrame: value.contains(";"),
                                sourceKind: "metadata",
                                source: "format metadata: \(format.rawValue)",
                                confidence: 0.8
                            )
                        }
                    }
                }
            }

        } catch {
            logger.debug("Failed to load metadata for timecode: \(error.localizedDescription)")
        }

        return nil
    }

    /// Validates if a string looks like a timecode.
    private func isValidTimecodeString(_ string: String) -> Bool {
        // Match patterns like "00:00:00:00", "01:02:03;04", "1:2:3:4"
        let pattern = #"^\d{1,2}[:;]\d{1,2}[:;]\d{1,2}[:;]\d{1,2}$"#
        return string.range(of: pattern, options: .regularExpression) != nil
    }

    /// Normalizes a timecode string to HH:MM:SS:FF format.
    private func normalizeTimecodeString(_ string: String) -> String {
        // Split by either : or ;
        let components = string.components(separatedBy: CharacterSet(charactersIn: ":;"))
        guard components.count == 4 else { return string }

        let hh = Int(components[0]) ?? 0
        let mm = Int(components[1]) ?? 0
        let ss = Int(components[2]) ?? 0
        let ff = Int(components[3]) ?? 0

        // Preserve original separator style (drop-frame uses ;)
        let separator = string.contains(";") ? ";" : ":"

        return String(format: "%02d:%02d:%02d%@%02d", hh, mm, ss, separator, ff)
    }
}
