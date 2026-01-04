//
//  CYBMedia+Bridge.swift
//  CYBMediaHolder
//
//  Bridge utilities for migrating from CYBMedia to MediaHolder.
//  Provides conversion functions and compatibility layer.
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Migration Types

/// Result of migrating a CYBMedia item.
public enum MigrationResult: Sendable {
    /// Successfully migrated to MediaHolder.
    case success(MediaHolder)

    /// Migration failed with error.
    case failure(MigrationError)
}

/// Errors that can occur during migration.
public enum MigrationError: Error, Sendable, CustomStringConvertible {
    /// The source CYBMedia is in offline state.
    case sourceOffline

    /// Failed to resolve the file location.
    case locationResolutionFailed

    /// Failed to probe the media.
    case probeFailed(Error)

    /// Unsupported media type.
    case unsupportedMediaType

    /// Missing required data.
    case missingData(String)

    public var description: String {
        switch self {
        case .sourceOffline:
            return "Source media is in offline state"
        case .locationResolutionFailed:
            return "Failed to resolve file location"
        case .probeFailed(let error):
            return "Media probe failed: \(error.localizedDescription)"
        case .unsupportedMediaType:
            return "Unsupported media type"
        case .missingData(let field):
            return "Missing required data: \(field)"
        }
    }
}

// MARK: - Migration Context

/// Context for CYBMedia migration.
///
/// Holds information extracted from CYBMedia for creating MediaHolder.
/// This structure maps CYBMedia properties to MediaHolder equivalents.
public struct CYBMediaMigrationContext: Sendable {
    /// Original UUID from CYBMedia.
    public let originalID: UUID

    /// File path from CYBMedia.
    public let filePath: String

    /// Display name from CYBMedia.
    public let name: String

    /// Security-scoped bookmark data.
    public let bookmark: Data?

    /// Whether the original was offline.
    public let wasOffline: Bool

    /// Content type (UTType identifier).
    public let contentTypeIdentifier: String?

    /// Creates a migration context.
    public init(
        originalID: UUID,
        filePath: String,
        name: String,
        bookmark: Data?,
        wasOffline: Bool,
        contentTypeIdentifier: String?
    ) {
        self.originalID = originalID
        self.filePath = filePath
        self.name = name
        self.bookmark = bookmark
        self.wasOffline = wasOffline
        self.contentTypeIdentifier = contentTypeIdentifier
    }
}

// MARK: - Migration Service

/// Service for migrating CYBMedia to MediaHolder.
///
/// ## Usage
/// ```swift
/// // Create migration context from CYBMedia
/// let context = CYBMediaMigrationContext(
///     originalID: cybVideo.id,
///     filePath: cybVideo.filePath,
///     name: cybVideo.name,
///     bookmark: cybVideo.bookmark,
///     wasOffline: cybVideo.isOffline,
///     contentTypeIdentifier: cybVideo.contentType?.identifier
/// )
///
/// // Migrate
/// let holder = try await MediaMigrationService.shared.migrate(from: context)
/// ```
public actor MediaMigrationService {

    /// Shared migration service instance.
    public static let shared = MediaMigrationService()

    /// Probe to use for migration.
    private let probe: MediaProbe

    private init() {
        self.probe = AVFoundationMediaProbe()
    }

    /// Migrates from a CYBMedia context to MediaHolder.
    ///
    /// - Parameter context: The migration context.
    /// - Returns: A new MediaHolder.
    /// - Throws: `MigrationError` if migration fails.
    public func migrate(from context: CYBMediaMigrationContext) async throws -> MediaHolder {
        // Check offline state
        if context.wasOffline {
            throw MigrationError.sourceOffline
        }

        // Create locator
        let locator: MediaLocator
        if let bookmark = context.bookmark {
            locator = .securityScopedBookmark(bookmark)
        } else if FileManager.default.fileExists(atPath: context.filePath) {
            locator = .filePath(context.filePath)
        } else {
            throw MigrationError.locationResolutionFailed
        }

        // Probe the media
        let descriptor: MediaDescriptor
        do {
            descriptor = try await probe.probe(locator: locator)
        } catch {
            throw MigrationError.probeFailed(error)
        }

        // Create MediaID preserving original UUID
        let bookmarkHash: String? = context.bookmark.map {
            String($0.base64EncodedString().prefix(16))
        }
        let id = MediaID(
            uuid: context.originalID,
            contentHash: nil,
            bookmarkHash: bookmarkHash
        )

        // Create MediaHolder
        return MediaHolder(
            id: id,
            locator: locator,
            descriptor: descriptor,
            displayName: context.name
        )
    }

    /// Batch migrates multiple CYBMedia contexts.
    ///
    /// - Parameter contexts: The migration contexts.
    /// - Returns: Array of migration results.
    public func migrateBatch(
        from contexts: [CYBMediaMigrationContext]
    ) async -> [MigrationResult] {
        var results: [MigrationResult] = []

        for context in contexts {
            do {
                let holder = try await migrate(from: context)
                results.append(.success(holder))
            } catch let error as MigrationError {
                results.append(.failure(error))
            } catch {
                results.append(.failure(.probeFailed(error)))
            }
        }

        return results
    }
}

// MARK: - Convenience Factory

/// Convenience factory for creating MediaHolder from common sources.
public enum MediaHolderFactory {

    /// Creates a MediaHolder from a file URL.
    ///
    /// - Parameters:
    ///   - url: The file URL.
    ///   - securityScoped: Whether to create security-scoped bookmark.
    /// - Returns: A new MediaHolder.
    /// - Throws: If creation fails.
    public static func create(
        from url: URL,
        securityScoped: Bool = false
    ) async throws -> MediaHolder {
        if securityScoped {
            return try await MediaHolder.createSecurityScoped(from: url)
        } else {
            return try await MediaHolder.create(from: url)
        }
    }

    /// Creates a MediaHolder from a file path.
    ///
    /// - Parameter path: The file path.
    /// - Returns: A new MediaHolder.
    /// - Throws: If creation fails.
    public static func create(fromPath path: String) async throws -> MediaHolder {
        let url = URL(fileURLWithPath: path)
        return try await MediaHolder.create(from: url)
    }

    /// Creates a MediaHolder from bookmark data.
    ///
    /// - Parameter bookmark: Security-scoped bookmark data.
    /// - Returns: A new MediaHolder.
    /// - Throws: If creation fails.
    public static func create(fromBookmark bookmark: Data) async throws -> MediaHolder {
        let locator = MediaLocator.securityScopedBookmark(bookmark)
        let probe = AVFoundationMediaProbe()
        let descriptor = try await probe.probe(locator: locator)

        let bookmarkHash = String(bookmark.base64EncodedString().prefix(16))
        let id = MediaID(bookmarkHash: bookmarkHash)

        // Resolve to get display name
        let resolved = try await locator.resolve()
        let displayName = resolved.url.lastPathComponent
        resolved.stopAccessing()

        return MediaHolder(
            id: id,
            locator: locator,
            descriptor: descriptor,
            displayName: displayName
        )
    }
}

// MARK: - CYBVideo Property Mapping Reference

/*
 CYBVideo Property Mapping to MediaHolder:

 CYBVideo.id                    -> MediaHolder.id.uuid (preserved via migration)
 CYBVideo.filePath              -> MediaHolder.locator.filePath
 CYBVideo.name                  -> MediaHolder.displayName
 CYBVideo.bookmark              -> MediaLocator.securityScopedBookmark
 CYBVideo.isOffline             -> (handled during migration)
 CYBVideo.contentType           -> MediaDescriptor.container.uniformTypeIdentifier

 CYBVideo.duration              -> MediaDescriptor.duration / durationSeconds
 CYBVideo.fps                   -> MediaDescriptor.primaryVideoTrack?.nominalFrameRate
 CYBVideo.timescale             -> MediaDescriptor.timebase
 CYBVideo.videoSize             -> MediaDescriptor.videoSize
 CYBVideo.videoFormat           -> MediaDescriptor.primaryVideoTrack?.codec.fourCC
 CYBVideo.audioFormat           -> MediaDescriptor.primaryAudioTrack?.codec.fourCC
 CYBVideo.timeRange             -> MediaDescriptor.primaryVideoTrack?.timeRange
 CYBVideo.hasAudio              -> MediaDescriptor.hasAudio
 CYBVideo.totalFrameNumber      -> MediaDescriptor.estimatedFrameCount
 CYBVideo.minFrameDuration      -> MediaDescriptor.primaryVideoTrack?.minFrameDuration

 CYBVideo.asset                 -> (removed - backend specific)
 CYBVideo.videoTrack            -> (removed - backend specific)
 CYBVideo.audioTrack            -> (removed - backend specific)
 CYBVideo.playerItem            -> (removed - player responsibility)
 CYBVideo.compositionInfo       -> (removed - player responsibility)
 CYBVideo.videoFormatDescription -> (internal to probe)
 CYBVideo.audioFormatDescription -> (internal to probe)

 CYBVideo.findVideoInformation() -> MediaHolderFactory.create() (probing now automatic)
 CYBVideo.setAVPlayerItem()      -> (player responsibility)
 CYBVideo.compositionInfo()      -> (player responsibility)
 */
