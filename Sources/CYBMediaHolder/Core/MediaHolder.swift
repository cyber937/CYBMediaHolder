//
//  MediaHolder.swift
//  CYBMediaHolder
//
//  Central type representing a single media item.
//  Combines identity, location, descriptor, and mutable store.
//

import Foundation

// MARK: - Timecode Availability

/// Timecode availability state for Player integration.
///
/// Players should check this before attempting to display timecode.
/// This enum represents the quality/confidence of available timecode data.
///
/// ## Usage
/// ```swift
/// let availability = await mediaHolder.timecodeAvailability()
/// switch availability {
/// case .available:
///     // High confidence timecode from tmcd track or metadata
///     showTimecode(mediaHolder.getTimecodeStart()!)
/// case .inferable:
///     // Low confidence estimated timecode
///     showTimecode(mediaHolder.getTimecodeStart()!, isEstimated: true)
/// case .unavailable:
///     // Should not occur in v1 (always at least inferable)
///     showPlaceholder("--:--:--:--")
/// }
/// ```
public enum TimecodeAvailability: Sendable, Equatable {

    /// Explicit timecode from tmcd track or metadata (high confidence).
    case available

    /// Inferred timecode - estimated, lower confidence (typically 00:00:00:00).
    case inferable

    /// Timecode not determinable (should not occur in v1).
    case unavailable
}

/// The central type representing a single media item.
///
/// `MediaHolder` is the primary interface for working with media in this framework.
/// It combines:
/// - `MediaID`: Stable identity
/// - `MediaLocator`: Location abstraction
/// - `MediaDescriptor`: Immutable facts about the media
/// - `MediaStore`: Mutable analysis/cache/annotations
/// - `Capability`: What operations are available
///
/// ## Design Principles
/// 1. **MediaHolder knows nothing about playback** - Players reference MediaHolder
/// 2. **Immutable vs mutable separation** - Descriptor is immutable, Store is mutable
/// 3. **Backend agnostic** - Works with AVFoundation, FFmpeg, RAW SDKs
/// 4. **Capability-driven UI** - Check capabilities before offering features
///
/// ## Usage
/// ```swift
/// // Create from URL
/// let holder = try await MediaHolder.create(from: url)
///
/// // Access descriptor
/// print(holder.descriptor.duration)
///
/// // Check capabilities
/// if holder.capabilities.contains(.waveformGeneratable) {
///     // Can generate waveform
/// }
///
/// // Update store (async)
/// await holder.store.setWaveform(waveformData, validity: validity)
/// ```
///
/// ## Thread Safety
/// - `id`, `locator`, `descriptor` are immutable and Sendable
/// - `store` is an actor, all mutations are async
/// - `capabilities` is computed, always reflects current state
///
/// ## Future Extensions
/// - Plugin system for RAW formats
/// - Remote media with progressive loading
/// - Multi-holder playlists/sequences
///
/// ## Thread Safety Note
/// This class is marked `@unchecked Sendable` because:
/// - All stored properties are either immutable (`id`, `locator`, `descriptor`, `displayName`)
///   or actor-isolated (`store: MediaStore`)
/// - No mutable state is directly accessible; all mutations go through the actor
/// - The class is `final` to prevent subclass violations
/// - Computed properties (`capabilities`, `baseCapabilities`) derive from Sendable sources
public final class MediaHolder: @unchecked Sendable {

    // MARK: - Properties

    /// Stable identifier for this media.
    public let id: MediaID

    /// Location of the media resource.
    public let locator: MediaLocator

    /// Immutable description of the media.
    public let descriptor: MediaDescriptor

    /// Extracted timecode information.
    /// This is an immutable fact about the media, not playback position.
    public let timecode: TimecodeExtractionResult?

    /// Mutable store for analysis, cache, and annotations.
    public let store: MediaStore

    /// Name for display purposes.
    public let displayName: String

    // MARK: - Computed Properties
    //
    // Naming Convention:
    // - Async computed properties (e.g., `capabilities`): Lightweight actor access,
    //   used when the value is derived from actor-isolated state with minimal computation.
    // - Async methods with `get` prefix (e.g., `getWaveform()`): Potentially heavier
    //   operations that may involve optional unwrapping, caching, or complex retrieval.
    //
    // This distinction helps callers understand the expected cost of each operation.

    /// Current capabilities based on descriptor, timecode, and store state.
    ///
    /// - Note: This is computed each time to reflect current analysis state.
    ///   Uses async property syntax as it's a lightweight actor access pattern.
    public var capabilities: Capability {
        get async {
            let analysisState = await store.analysisState
            return CapabilityCalculator.calculate(
                for: descriptor,
                backend: descriptor.probeBackend,
                analysisState: analysisState,
                timecode: timecode
            )
        }
    }

    /// Synchronous capabilities (without analysis state).
    ///
    /// - Note: Use this for quick checks; doesn't include analysis-based capabilities.
    ///   Does include timecode capabilities.
    public var baseCapabilities: Capability {
        CapabilityCalculator.calculate(
            for: descriptor,
            backend: descriptor.probeBackend,
            analysisState: nil,
            timecode: timecode
        )
    }

    // MARK: - Initialization

    /// Creates a MediaHolder with all components.
    ///
    /// - Parameters:
    ///   - id: The media ID.
    ///   - locator: The media locator.
    ///   - descriptor: The media descriptor.
    ///   - timecode: Extracted timecode information (optional).
    ///   - store: The media store (optional, creates new if nil).
    ///   - displayName: Display name (optional, derived from locator if nil).
    public init(
        id: MediaID,
        locator: MediaLocator,
        descriptor: MediaDescriptor,
        timecode: TimecodeExtractionResult? = nil,
        store: MediaStore? = nil,
        displayName: String? = nil
    ) {
        self.id = id
        self.locator = locator
        self.descriptor = descriptor
        self.timecode = timecode
        self.store = store ?? MediaStore()
        self.displayName = displayName ?? descriptor.fileName ?? "Untitled"
    }

    // MARK: - Factory Methods

    /// Image file extensions supported by ImageMediaProbe.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "tiff", "tif",
        "heic", "heif", "webp", "bmp", "ico"
    ]

    /// Determines if a URL points to an image file.
    private static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    /// Creates a MediaHolder from a URL using the appropriate probe.
    ///
    /// Automatically selects ImageMediaProbe for image files and
    /// AVFoundationMediaProbe for video/audio files.
    ///
    /// - Parameters:
    ///   - url: The URL to the media file.
    ///   - probe: The probe to use (default: auto-selected based on file type).
    ///   - validationConfig: Configuration for file validation (default: standard validation).
    /// - Returns: A new MediaHolder.
    /// - Throws: `MediaValidationError` if validation fails, or `MediaProbeError` if probing fails.
    public static func create(
        from url: URL,
        using probe: MediaProbe? = nil,
        validationConfig: MediaValidationConfig = .default
    ) async throws -> MediaHolder {
        // Validate file before loading
        let validator = MediaFileValidator(config: validationConfig)
        try validator.validate(url: url)

        // Create locator
        let locator: MediaLocator
        if url.isFileURL {
            locator = .filePath(url.path)
        } else {
            locator = .url(url)
        }

        // Select appropriate probe based on file type
        let selectedProbe = probe ?? (isImageFile(url) ? ImageMediaProbe() : AVFoundationMediaProbe())

        // For images, use simple probe (no timecode)
        if let imageProbe = selectedProbe as? ImageMediaProbe {
            let descriptor = try await imageProbe.probe(locator: locator)

            // Create ID
            let id = MediaID()

            return MediaHolder(
                id: id,
                locator: locator,
                descriptor: descriptor,
                timecode: nil, // Images don't have timecode
                displayName: url.lastPathComponent
            )
        }

        // For video/audio, use extended probe (includes timecode)
        let avProbe = selectedProbe as? AVFoundationMediaProbe ?? AVFoundationMediaProbe()
        let extendedResult = try await avProbe.probeExtended(locator: locator)

        // Create ID
        let id = MediaID()

        // Create holder with timecode
        return MediaHolder(
            id: id,
            locator: locator,
            descriptor: extendedResult.descriptor,
            timecode: extendedResult.timecode,
            displayName: url.lastPathComponent
        )
    }

    /// Creates a MediaHolder from a security-scoped URL.
    ///
    /// Automatically selects ImageMediaProbe for image files and
    /// AVFoundationMediaProbe for video/audio files.
    ///
    /// - Parameters:
    ///   - url: The security-scoped URL.
    ///   - probe: The probe to use (default: auto-selected based on file type).
    ///   - validationConfig: Configuration for file validation (default: standard validation).
    /// - Returns: A new MediaHolder.
    /// - Throws: `MediaValidationError` if validation fails, or `MediaProbeError` if probing fails.
    public static func createSecurityScoped(
        from url: URL,
        using probe: MediaProbe? = nil,
        validationConfig: MediaValidationConfig = .default
    ) async throws -> MediaHolder {
        // Validate file before loading
        let validator = MediaFileValidator(config: validationConfig)
        try validator.validate(url: url)

        // Create security-scoped locator
        let locator = try MediaLocator.fromSecurityScopedURL(url)

        // Create ID with bookmark hash
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let bookmarkHash = bookmarkData.base64EncodedString().prefix(16)
        let id = MediaID(bookmarkHash: String(bookmarkHash))

        // Select appropriate probe based on file type
        let selectedProbe = probe ?? (isImageFile(url) ? ImageMediaProbe() : AVFoundationMediaProbe())

        // For images, use simple probe (no timecode)
        if let imageProbe = selectedProbe as? ImageMediaProbe {
            let descriptor = try await imageProbe.probe(locator: locator)

            return MediaHolder(
                id: id,
                locator: locator,
                descriptor: descriptor,
                timecode: nil, // Images don't have timecode
                displayName: url.lastPathComponent
            )
        }

        // For video/audio, use extended probe (includes timecode)
        let avProbe = selectedProbe as? AVFoundationMediaProbe ?? AVFoundationMediaProbe()
        let extendedResult = try await avProbe.probeExtended(locator: locator)

        // Create holder with timecode
        return MediaHolder(
            id: id,
            locator: locator,
            descriptor: extendedResult.descriptor,
            timecode: extendedResult.timecode,
            displayName: url.lastPathComponent
        )
    }

    /// Creates a MediaHolder from a MediaLocator.
    ///
    /// This is the most flexible factory method, accepting any locator type
    /// (file path, security-scoped bookmark, URL, etc.).
    ///
    /// - Parameters:
    ///   - locator: The media locator.
    ///   - probe: The probe to use (default: AVFoundationMediaProbe).
    ///   - displayName: Optional display name (derived from locator if nil).
    /// - Returns: A new MediaHolder.
    /// - Throws: If probing fails.
    ///
    /// ## Usage
    /// ```swift
    /// // From file path
    /// let locator = MediaLocator.filePath("/path/to/video.mp4")
    /// let holder = try await MediaHolder.create(from: locator)
    ///
    /// // From security-scoped bookmark
    /// let bookmarkLocator = MediaLocator.securityScopedBookmark(bookmarkData)
    /// let holder = try await MediaHolder.create(from: bookmarkLocator)
    /// ```
    public static func create(
        from locator: MediaLocator,
        using probe: MediaProbe = AVFoundationMediaProbe(),
        displayName: String? = nil
    ) async throws -> MediaHolder {
        // Probe the media with extended result (includes timecode)
        let avProbe = probe as? AVFoundationMediaProbe ?? AVFoundationMediaProbe()
        let extendedResult = try await avProbe.probeExtended(locator: locator)

        // Create ID
        let id = MediaID()

        // Derive display name from locator if not provided
        let name = displayName ?? deriveDisplayName(from: locator, descriptor: extendedResult.descriptor)

        // Create holder with timecode
        return MediaHolder(
            id: id,
            locator: locator,
            descriptor: extendedResult.descriptor,
            timecode: extendedResult.timecode,
            displayName: name
        )
    }

    /// Derives a display name from a locator.
    private static func deriveDisplayName(
        from locator: MediaLocator,
        descriptor: MediaDescriptor
    ) -> String {
        // Try to get name from descriptor first
        if let fileName = descriptor.fileName {
            return fileName
        }

        // Fall back to locator info
        switch locator {
        case .filePath(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        case .url(let url):
            return url.lastPathComponent
        case .http(let url, _):
            return url.lastPathComponent
        case .s3(_, let key, _):
            return URL(string: key)?.lastPathComponent ?? key
        case .securityScopedBookmark:
            return "Media"
        }
    }

    // MARK: - Convenience Properties

    /// Duration in seconds.
    public var duration: Double {
        descriptor.durationSeconds
    }

    /// Whether this is video content.
    public var isVideo: Bool {
        descriptor.mediaType == .video
    }

    /// Whether this is audio-only content.
    public var isAudioOnly: Bool {
        descriptor.mediaType == .audio
    }

    /// Whether this is an image.
    public var isImage: Bool {
        descriptor.mediaType == .image
    }

    /// Video size (if video).
    public var videoSize: CGSize? {
        descriptor.videoSize
    }

    /// Frame rate (if video).
    public var frameRate: Float? {
        descriptor.frameRate
    }

    /// Whether this is HDR content.
    public var isHDR: Bool {
        descriptor.isHDR
    }

    /// Whether this is local media.
    public var isLocal: Bool {
        locator.isLocal
    }

    // MARK: - Store Convenience Methods
    //
    // These use the `get` prefix convention to indicate:
    // 1. Actor-isolated access (requires await)
    // 2. Data retrieval that may return optional values
    // 3. Semantically distinct from simple property access
    //
    // Contrast with `capabilities` async property which is a computed derivation.

    /// Gets analysis state asynchronously.
    ///
    /// - Returns: Current analysis state from the media store.
    public func getAnalysisState() async -> AnalysisState {
        await store.analysisState
    }

    /// Gets waveform data if available.
    ///
    /// - Returns: Waveform data if it has been generated, nil otherwise.
    public func getWaveform() async -> WaveformData? {
        await store.analysisState.waveform
    }

    /// Gets peak data if available.
    ///
    /// - Returns: Peak data if it has been generated, nil otherwise.
    public func getPeak() async -> PeakData? {
        await store.analysisState.peak
    }

    /// Gets keyframe index if available.
    ///
    /// - Returns: Keyframe index if it has been built, nil otherwise.
    public func getKeyframeIndex() async -> KeyframeIndex? {
        await store.analysisState.keyframeIndex
    }

    /// Gets user annotations.
    ///
    /// - Returns: User annotations associated with this media.
    public func getAnnotations() async -> UserAnnotations {
        await store.userAnnotations
    }

    // MARK: - Timecode Access

    /// Returns timecode availability status.
    ///
    /// Player should check this before displaying timecode to determine
    /// the confidence level of the timecode data.
    ///
    /// - Returns: The availability status of timecode data.
    public func timecodeAvailability() -> TimecodeAvailability {
        guard let tc = timecode else {
            return .unavailable
        }

        switch tc.sourceKind {
        case "tmcd", "metadata":
            return .available
        case "inferred":
            return .inferable
        default:
            return .inferable
        }
    }

    /// Gets the start timecode string.
    ///
    /// - Returns: Start timecode (e.g., "01:00:00:00"), or nil if unavailable.
    public func getTimecodeStart() -> String? {
        timecode?.start
    }

    /// Gets the timecode rate (frame rate).
    ///
    /// - Returns: Timecode rate (e.g., 24, 29.97), or nil if unavailable.
    public func getTimecodeRate() -> Double? {
        timecode?.rate
    }

    /// Gets the drop-frame flag.
    ///
    /// - Returns: True if timecode uses drop-frame format, false otherwise.
    public func getTimecodeDropFrame() -> Bool {
        timecode?.dropFrame ?? false
    }

    /// Gets the timecode source kind.
    ///
    /// - Returns: Source kind ("tmcd", "metadata", "inferred"), or nil if unavailable.
    public func getTimecodeSourceKind() -> String? {
        timecode?.sourceKind
    }

    /// Creates a `CoreNormalizedStore` with all metadata including timecode.
    ///
    /// - Parameter source: Provenance source identifier (default: uses probe backend).
    /// - Returns: A populated `CoreNormalizedStore` with all metadata.
    public func makeCoreNormalizedStoreWithTimecode(source: String? = nil) -> CoreNormalizedStore {
        if let tc = timecode {
            return descriptor.makeCoreNormalizedStore(timecode: tc, source: source)
        } else {
            return descriptor.makeCoreNormalizedStore(source: source)
        }
    }
}

// MARK: - Identifiable

extension MediaHolder: Identifiable {
    // Uses MediaID.uuid as the identifier
}

// MARK: - Hashable

extension MediaHolder: Hashable {
    public static func == (lhs: MediaHolder, rhs: MediaHolder) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CustomStringConvertible

extension MediaHolder: CustomStringConvertible {
    public var description: String {
        let timecodeDesc: String
        if let tc = timecode {
            timecodeDesc = "Timecode: \(tc.start) @ \(tc.rate) fps (\(tc.sourceKind))"
        } else {
            timecodeDesc = "Timecode: none"
        }

        return """
        MediaHolder(\(displayName))
          ID: \(id)
          Type: \(descriptor.mediaType)
          Duration: \(String(format: "%.2f", duration))s
          \(descriptor.hasVideo ? "Video: \(Int(videoSize?.width ?? 0))x\(Int(videoSize?.height ?? 0)) @ \(frameRate ?? 0) fps" : "No video")
          \(descriptor.hasAudio ? "Audio: \(descriptor.audioTracks.count) track(s)" : "No audio")
          \(timecodeDesc)
          Capabilities: \(baseCapabilities)
        """
    }
}
