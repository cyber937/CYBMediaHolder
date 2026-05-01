//
//  MediaProbe.swift
//  CYBMediaHolder
//
//  Protocol for probing media files to extract descriptors.
//  Allows backend-agnostic media inspection.
//

import Foundation

/// Errors that can occur during media probing.
public enum MediaProbeError: Error, Sendable, CustomStringConvertible {
    /// File not found at the specified location.
    case fileNotFound(String)

    /// Failed to resolve the media locator.
    case locatorResolutionFailed(Error)

    /// The file format is not supported by this probe.
    case unsupportedFormat(String)

    /// The file is not playable/readable.
    case notPlayable(reason: String)

    /// Failed to load media properties.
    case propertyLoadFailed(Error)

    /// No tracks found in the media.
    case noTracksFound

    /// Security access denied (sandbox).
    case accessDenied

    /// Generic probe failure.
    case probeFailed(Error)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .locatorResolutionFailed(let error):
            return "Locator resolution failed: \(error.localizedDescription)"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .notPlayable(let reason):
            return "Media not playable: \(reason)"
        case .propertyLoadFailed(let error):
            return "Property load failed: \(error.localizedDescription)"
        case .noTracksFound:
            return "No media tracks found in file"
        case .accessDenied:
            return "Security access denied (sandbox restriction)"
        case .probeFailed(let error):
            return "Probe failed: \(error.localizedDescription)"
        }
    }

    /// Whether trying a different probe might succeed for this error.
    ///
    /// Codec / container / format / playability issues are recoverable — another
    /// probe (e.g. FFmpeg fallback after AVFoundation) might handle the file.
    /// File-system errors (missing file, sandbox denial) are absolute and should
    /// not trigger a fallback.
    public var isCodecOrFormatFailure: Bool {
        switch self {
        case .unsupportedFormat, .notPlayable, .propertyLoadFailed, .noTracksFound, .probeFailed:
            return true
        case .fileNotFound, .locatorResolutionFailed, .accessDenied:
            return false
        }
    }
}

/// Protocol for probing media files to extract descriptors.
///
/// `MediaProbe` implementations extract `MediaDescriptor` from various
/// sources using different backends (AVFoundation, FFmpeg, etc.).
///
/// ## Design Notes
/// - Probing should be async and cancellable
/// - Probes should not hold onto resources after completion
/// - Multiple probe implementations can be registered
///
/// ## Future Extensions
/// - FFmpegMediaProbe for unsupported formats
/// - REDMediaProbe, BRAWMediaProbe for RAW formats
/// - RemoteMediaProbe for HTTP range requests
public protocol MediaProbe: Sendable {

    /// Unique identifier for this probe implementation.
    var identifier: String { get }

    /// Human-readable name for this probe.
    var displayName: String { get }

    /// File extensions this probe can handle.
    var supportedExtensions: Set<String> { get }

    /// UTTypes this probe can handle.
    var supportedUTTypes: Set<String> { get }

    /// Probes a media locator and returns a descriptor.
    ///
    /// - Parameter locator: The media locator to probe.
    /// - Returns: A MediaDescriptor with all extracted information.
    /// - Throws: `MediaProbeError` if probing fails.
    func probe(locator: MediaLocator) async throws -> MediaDescriptor

    /// Checks if this probe can handle the given locator.
    ///
    /// - Parameter locator: The media locator to check.
    /// - Returns: True if this probe can likely handle the media.
    func canHandle(locator: MediaLocator) -> Bool
}

// MARK: - Default Implementation

extension MediaProbe {

    /// Default extension check based on supportedExtensions.
    public func canHandle(locator: MediaLocator) -> Bool {
        guard let path = locator.filePath else {
            // For non-file locators, assume we can try
            return true
        }

        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }
}

// MARK: - Probe Registry

/// Registry for managing multiple probe implementations.
///
/// Allows registering and selecting probes based on media type.
///
/// ## Future Extensions
/// - Plugin-based probe registration
/// - Probe priority/preference system
/// - Fallback chain for probe failures
public actor MediaProbeRegistry {

    /// Shared registry instance.
    public static let shared = MediaProbeRegistry()

    /// Registered probes.
    private var probes: [MediaProbe] = []

    /// Default probe to use.
    private var defaultProbe: MediaProbe?

    private init() {
        // Register ImageIO probe first (more specific)
        let imageProbe = ImageMediaProbe()
        probes.append(imageProbe)

        // Register AVFoundation probe as default for video/audio
        let avProbe = AVFoundationMediaProbe()
        probes.append(avProbe)
        defaultProbe = avProbe
    }

    /// Internal initializer for tests — produces a fresh, empty registry.
    internal init(empty: Void) {
        // Empty — tests register their own probes.
    }

    /// Registers a probe.
    public func register(_ probe: MediaProbe) {
        probes.append(probe)
    }

    /// Sets the default probe.
    public func setDefault(_ probe: MediaProbe) {
        defaultProbe = probe
    }

    /// Gets the best probe for a locator.
    ///
    /// - Parameter locator: The media locator.
    /// - Returns: The best probe for this locator, or the default.
    public func probe(for locator: MediaLocator) -> MediaProbe {
        // Find first probe that can handle this locator
        if let probe = probes.first(where: { $0.canHandle(locator: locator) }) {
            return probe
        }
        // Fall back to default
        return defaultProbe ?? AVFoundationMediaProbe()
    }

    /// Gets all registered probes.
    public var registeredProbes: [MediaProbe] {
        probes
    }

    /// Probes a locator using the best available probe, with fallback.
    ///
    /// Tries every registered probe whose `canHandle(locator:)` returns true,
    /// in registration order. If a probe throws a recoverable error
    /// (`MediaProbeError.isCodecOrFormatFailure == true`), the next candidate
    /// is tried. Non-recoverable errors (file-system / sandbox) propagate
    /// immediately. If no probe matches, falls back to `defaultProbe`.
    ///
    /// This enables patterns like "AVFoundation first, FFmpeg fallback for
    /// MXF / professional codecs": both probes claim `.mxf`, AVFoundation
    /// is tried first (fast, native), and FFmpeg picks up the slack when
    /// `AVAsset.load(...)` fails on unsupported codecs.
    ///
    /// - Parameter locator: The media locator.
    /// - Returns: A MediaDescriptor produced by the first successful probe.
    /// - Throws: The last recoverable error if every candidate fails, or any
    ///   non-recoverable error encountered along the way.
    public func probe(locator: MediaLocator) async throws -> MediaDescriptor {
        let candidates = probes.filter { $0.canHandle(locator: locator) }

        if candidates.isEmpty {
            guard let fallback = defaultProbe else {
                throw MediaProbeError.unsupportedFormat("No registered probe matched and no default probe is set")
            }
            return try await fallback.probe(locator: locator)
        }

        var lastRecoverableError: MediaProbeError?
        for candidate in candidates {
            do {
                return try await candidate.probe(locator: locator)
            } catch let error as MediaProbeError where error.isCodecOrFormatFailure {
                lastRecoverableError = error
                continue
            }
        }

        throw lastRecoverableError ?? MediaProbeError.unsupportedFormat("All registered probes rejected the file")
    }
}
