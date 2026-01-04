//
//  ThumbnailIndex.swift
//  CYBMediaHolder
//
//  Thumbnail index for preview scrubbing.
//

import Foundation

/// Thumbnail index for preview scrubbing.
///
/// Contains references to pre-generated thumbnail images at regular intervals.
/// Used for timeline scrubbing and preview popups during seek operations.
///
/// ## Usage
/// ```swift
/// // Get thumbnail for time position
/// let index = Int(time / thumbnailIndex.intervalSeconds)
/// let path = thumbnailIndex.thumbnailPaths[index]
/// ```
public struct ThumbnailIndex: Codable, Sendable {

    /// Thumbnail generation interval in seconds.
    public let intervalSeconds: Double

    /// Paths or identifiers to thumbnail images.
    public let thumbnailPaths: [String]

    /// Generation timestamp.
    public let generatedAt: Date

    /// Creates a thumbnail index with the specified parameters.
    ///
    /// - Parameters:
    ///   - intervalSeconds: Time interval between thumbnails.
    ///   - thumbnailPaths: Paths or identifiers for each thumbnail.
    public init(intervalSeconds: Double, thumbnailPaths: [String]) {
        self.intervalSeconds = intervalSeconds
        self.thumbnailPaths = thumbnailPaths
        self.generatedAt = Date()
    }

    /// Gets the thumbnail path for a given time.
    ///
    /// - Parameter time: Time in seconds.
    /// - Returns: Path to the thumbnail, or nil if out of range.
    public func thumbnailPath(for time: Double) -> String? {
        guard time >= 0, intervalSeconds > 0 else { return nil }
        let index = Int(time / intervalSeconds)
        guard index >= 0, index < thumbnailPaths.count else { return nil }
        return thumbnailPaths[index]
    }
}
