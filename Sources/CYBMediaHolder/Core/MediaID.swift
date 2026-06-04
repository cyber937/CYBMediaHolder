//
//  MediaID.swift
//  CYBMediaHolder
//
//  Stable identifier for media, independent of file path.
//  Supports future MAM/remote integration via optional content hash.
//

import Foundation
import CryptoKit

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

// MARK: - Equality

extension MediaID {

    /// Identity is the `uuid` alone.
    ///
    /// When a holder is created from a local file the `uuid` is derived from the
    /// file's content (see ``contentStableIdentity(forFileAt:)``), so two holders
    /// for the same file compare equal and hash equally. `contentHash` and
    /// `bookmarkHash` are informational metadata and do not affect identity.
    public static func == (lhs: MediaID, rhs: MediaID) -> Bool {
        lhs.uuid == rhs.uuid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}

// MARK: - Content-stable Identity

extension MediaID {

    /// Derives a content-stable identity for a local file.
    ///
    /// The returned `uuid` is computed from a fingerprint of the file (its size
    /// plus up to 64 KiB each of the head and tail), so the same file yields the
    /// same identity across launches and after moves/copies. `contentHash` is the
    /// full SHA-256 hex digest of that fingerprint.
    ///
    /// - Parameter url: A local file URL.
    /// - Returns: The derived identity, or `nil` for non-file URLs / unreadable files.
    public static func contentStableIdentity(forFileAt url: URL) -> (uuid: UUID, contentHash: String)? {
        guard let fingerprint = fileFingerprint(url) else { return nil }
        let digest = SHA256.hash(data: fingerprint)
        let bytes = Array(digest)               // 32 bytes
        let u = Array(bytes.prefix(16))
        let uuid = UUID(uuid: (u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7],
                               u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]))
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return (uuid, hex)
    }

    /// Builds a fingerprint from the file size and up to 64 KiB each of the head
    /// and tail. Deliberately content-based (no mtime) so identity survives
    /// copies and restores.
    private static func fileFingerprint(_ url: URL) -> Data? {
        guard url.isFileURL else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var data = Data()
        var sizeLE = size.littleEndian
        withUnsafeBytes(of: &sizeLE) { data.append(contentsOf: $0) }

        let chunk = 64 * 1024
        let head = (try? handle.read(upToCount: chunk)) ?? Data()
        data.append(head)

        // Include the tail too when the file is large enough that head + tail
        // don't overlap, to lower the collision risk for media that share a
        // common header.
        if size > UInt64(2 * chunk) {
            try? handle.seek(toOffset: size - UInt64(chunk))
            let tail = (try? handle.read(upToCount: chunk)) ?? Data()
            data.append(tail)
        }
        return data
    }
}
