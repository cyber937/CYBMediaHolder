//
//  MediaCache.swift
//  CYBMediaHolder
//
//  Protocol for caching media analysis and generated data.
//  Allows pluggable cache backends (memory, disk, network).
//

import Foundation

/// Keys for cache entries.
public struct MediaCacheKey: Hashable, Sendable {
    /// The media ID this cache entry belongs to.
    public let mediaID: MediaID

    /// The type of cached data.
    public let dataType: CacheDataType

    /// Optional variant identifier (e.g., resolution for thumbnails).
    public let variant: String?

    public init(mediaID: MediaID, dataType: CacheDataType, variant: String? = nil) {
        self.mediaID = mediaID
        self.dataType = dataType
        self.variant = variant
    }
}

/// Types of data that can be cached.
public enum CacheDataType: String, Sendable, CaseIterable {
    case waveform
    case peak
    case keyframeIndex
    case thumbnailIndex
    case thumbnail
    case descriptor
    case storeSnapshot
}

/// Protocol for media cache implementations.
///
/// `MediaCache` provides an abstraction over different cache backends:
/// - In-memory cache (fast, volatile)
/// - Disk cache (persistent, larger capacity)
/// - Network cache (shared, distributed)
///
/// ## Design Notes
/// - All operations are async for flexibility
/// - Expiration policies are implementation-specific
/// - Cache entries are keyed by MediaID + data type
///
/// ## Future Extensions
/// - LRU eviction policies
/// - Size limits
/// - Compression
/// - Encryption for sensitive data
public protocol MediaCache: Actor {

    /// Stores data in the cache.
    ///
    /// - Parameters:
    ///   - data: The data to cache (must be Codable).
    ///   - key: The cache key.
    func store<T: Codable & Sendable>(_ data: T, for key: MediaCacheKey) async throws

    /// Retrieves data from the cache.
    ///
    /// - Parameters:
    ///   - type: The expected type of the cached data.
    ///   - key: The cache key.
    /// - Returns: The cached data, or nil if not found.
    func retrieve<T: Codable & Sendable>(_ type: T.Type, for key: MediaCacheKey) async throws -> T?

    /// Removes data from the cache.
    ///
    /// - Parameter key: The cache key.
    func remove(for key: MediaCacheKey) async

    /// Removes all cache entries for a media ID.
    ///
    /// - Parameter mediaID: The media ID.
    func removeAll(for mediaID: MediaID) async

    /// Clears the entire cache.
    func clear() async

    /// Checks if a cache entry exists.
    ///
    /// - Parameter key: The cache key.
    /// - Returns: True if the entry exists.
    func contains(_ key: MediaCacheKey) async -> Bool

    /// Gets cache statistics.
    func statistics() async -> CacheStatistics
}

/// Cache statistics.
public struct CacheStatistics: Sendable {
    /// Number of entries in the cache.
    public let entryCount: Int

    /// Estimated memory usage in bytes.
    public let memoryUsageBytes: Int

    /// Cache hit count since creation.
    public let hitCount: Int

    /// Cache miss count since creation.
    public let missCount: Int

    /// Hit rate (0.0 to 1.0).
    public var hitRate: Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0
    }

    public init(entryCount: Int, memoryUsageBytes: Int, hitCount: Int, missCount: Int) {
        self.entryCount = entryCount
        self.memoryUsageBytes = memoryUsageBytes
        self.hitCount = hitCount
        self.missCount = missCount
    }
}

/// Errors that can occur during cache operations.
public enum MediaCacheError: Error, Sendable, CustomStringConvertible {
    /// Failed to encode data for caching.
    case encodingFailed(Error)

    /// Failed to decode cached data.
    case decodingFailed(Error)

    /// Cache storage is full.
    case storageFull

    /// IO error during disk cache operations.
    case ioError(Error)

    /// Cache entry has expired.
    case expired

    public var description: String {
        switch self {
        case .encodingFailed(let error):
            return "Cache encoding failed: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Cache decoding failed: \(error.localizedDescription)"
        case .storageFull:
            return "Cache storage is full"
        case .ioError(let error):
            return "Cache I/O error: \(error.localizedDescription)"
        case .expired:
            return "Cache entry has expired"
        }
    }
}
