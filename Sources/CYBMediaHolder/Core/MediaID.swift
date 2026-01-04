//
//  MediaID.swift
//  CYBMediaHolder
//
//  Stable identifier for media, independent of file path.
//  Supports future MAM/remote integration via optional content hash.
//

import Foundation

/// A stable, unique identifier for a media item.
///
/// `MediaID` provides identity that persists across:
/// - File moves/renames (via UUID)
/// - Storage backends (local, remote, MAM)
/// - Application sessions (via Codable)
///
/// ## Design Notes
/// - `uuid`: Always present, generated at creation
/// - `contentHash`: Optional, computed from file content for deduplication
/// - `bookmarkHash`: Optional, derived from security-scoped bookmark for macOS sandbox
///
/// ## Future Extensions
/// - MAM integration can use `contentHash` for asset matching
/// - Remote storage can use hash for integrity verification
public struct MediaID: Hashable, Codable, Sendable {

    /// Unique identifier, generated at creation time.
    public let uuid: UUID

    /// Optional content-based hash for deduplication and integrity.
    /// Computed from file content (e.g., first N bytes + size + mtime).
    /// - Note: May be nil if not yet computed or not applicable (e.g., remote streams).
    public let contentHash: String?

    /// Optional hash derived from security-scoped bookmark.
    /// Useful for macOS sandbox environments.
    public let bookmarkHash: String?

    /// Creates a new MediaID with a fresh UUID.
    ///
    /// - Parameters:
    ///   - contentHash: Optional content-based hash for deduplication.
    ///   - bookmarkHash: Optional bookmark-derived hash.
    public init(contentHash: String? = nil, bookmarkHash: String? = nil) {
        self.uuid = UUID()
        self.contentHash = contentHash
        self.bookmarkHash = bookmarkHash
    }

    /// Creates a MediaID with a specific UUID (for deserialization/migration).
    ///
    /// - Parameters:
    ///   - uuid: The UUID to use.
    ///   - contentHash: Optional content-based hash.
    ///   - bookmarkHash: Optional bookmark-derived hash.
    public init(uuid: UUID, contentHash: String? = nil, bookmarkHash: String? = nil) {
        self.uuid = uuid
        self.contentHash = contentHash
        self.bookmarkHash = bookmarkHash
    }
}

// MARK: - CustomStringConvertible

extension MediaID: CustomStringConvertible {
    public var description: String {
        var parts = ["MediaID(\(uuid.uuidString.prefix(8))...)"]
        if let hash = contentHash {
            parts.append("hash:\(hash.prefix(8))...")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Identifiable

extension MediaID: Identifiable {
    public var id: UUID { uuid }
}
