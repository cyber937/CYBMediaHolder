//
//  DiskMediaCache.swift
//  CYBMediaHolder
//
//  Disk-based persistent cache for media analysis data.
//  Uses Swift Codable for serialization.
//

import Foundation

/// Disk-based cache implementation with persistence.
///
/// Stores cached data to disk, surviving app restarts.
/// Uses PropertyListEncoder for efficient Codable serialization.
///
/// ## Features
/// - Persistent storage across app launches
/// - Size-limited with LRU eviction
/// - Thread-safe via actor isolation
/// - Automatic directory creation
///
/// ## Storage Location
/// `~/Library/Caches/CYBMediaHolder/`
///
/// ## Usage
/// ```swift
/// let cache = DiskMediaCache(maxSizeBytes: 100_000_000)
/// try await cache.store(waveform, for: key)
/// let cached = try await cache.retrieve(WaveformData.self, for: key)
/// ```
///
/// ## Performance Characteristics
///
/// ### Current Implementation
/// - **LRU Eviction**: O(n) linear search through `metadataIndex` to find
///   the least recently used entry.
/// - **Lookup/Store**: O(1) dictionary access via `metadataIndex`.
/// - **Disk I/O**: File operations dominate actual performance.
///
/// ### Trade-off Analysis
/// Unlike `InMemoryMediaCache` which uses O(1) doubly-linked list for LRU,
/// this implementation uses O(n) linear search. This is acceptable because:
///
/// 1. **Disk I/O dominates**: File read/write operations are orders of magnitude
///    slower than in-memory operations. The O(n) search adds microseconds
///    while disk I/O takes milliseconds.
///
/// 2. **Typical cache size**: Disk caches typically hold hundreds to thousands
///    of entries, not millions. Linear search through ~1000 entries is ~1ms.
///
/// 3. **Eviction frequency**: LRU eviction only occurs when the cache is full,
///    which is infrequent compared to normal read/write operations.
///
/// 4. **Complexity vs. benefit**: Maintaining a heap or linked list across
///    app restarts requires additional persistence logic and metadata,
///    increasing complexity without proportional performance benefit.
///
/// ### Future Optimization Paths
/// If profiling shows LRU eviction as a bottleneck:
///
/// 1. **Min-Heap approach**: Store `(accessTime, key)` tuples in a min-heap.
///    - Extract-min: O(log n)
///    - Update on access: O(n) to find + O(log n) to re-heapify
///    - Persistence: Rebuild heap on load from metadata
///
/// 2. **Approximate LRU**: Use time-bucketed eviction (evict entries from
///    oldest bucket) for O(1) amortized eviction at cost of precision.
///
/// 3. **Lazy eviction**: Mark entries for eviction, batch delete on app
///    background/termination to reduce per-operation overhead.
public actor DiskMediaCache: MediaCache {

    // MARK: - Types

    /// Metadata for a cached file.
    private struct CacheMetadata: Codable {
        let key: CodableCacheKey
        let createdAt: Date
        var accessedAt: Date
        let sizeBytes: Int
        let dataTypeName: String

        mutating func markAccessed() {
            accessedAt = Date()
        }
    }

    /// Codable wrapper for MediaCacheKey.
    private struct CodableCacheKey: Codable, Hashable {
        let mediaIDHash: String
        let dataType: String
        let variant: String?

        init(from key: MediaCacheKey) {
            self.mediaIDHash = key.mediaID.hashValue.description
            self.dataType = key.dataType.rawValue
            self.variant = key.variant
        }

        var filename: String {
            let variantPart = variant.map { "_\($0)" } ?? ""
            return "\(mediaIDHash)_\(dataType)\(variantPart).cache"
        }
    }

    // MARK: - Properties

    /// Cache directory URL.
    private let cacheDirectory: URL

    /// Maximum cache size in bytes.
    private let maxSizeBytes: Int

    /// Maximum age of entries in seconds.
    private let maxAge: TimeInterval

    /// Metadata index for fast lookups.
    private var metadataIndex: [String: CacheMetadata] = [:]

    /// Statistics.
    private var hitCount = 0
    private var missCount = 0

    /// Current total cache size.
    private var currentSizeBytes = 0

    /// Encoder for data serialization.
    private let encoder = PropertyListEncoder()

    /// Decoder for data deserialization.
    private let decoder = PropertyListDecoder()

    /// File manager.
    private let fileManager = FileManager.default

    // MARK: - Initialization

    /// Creates a disk cache.
    ///
    /// - Parameters:
    ///   - cacheDirectory: Directory for cache files. If nil, uses default location.
    ///   - maxSizeBytes: Maximum total cache size (default: 500MB).
    ///   - maxAge: Maximum age in seconds (default: 7 days).
    public init(
        cacheDirectory: URL? = nil,
        maxSizeBytes: Int = 500_000_000,
        maxAge: TimeInterval = 604800
    ) {
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory
        self.maxSizeBytes = maxSizeBytes
        self.maxAge = maxAge

        // Initialization is sync, but we need to load metadata async
        // This will be done lazily on first access
    }

    /// Default cache directory.
    private static var defaultCacheDirectory: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("CYBMediaHolder", isDirectory: true)
    }

    private static var fileManager: FileManager { .default }

    // MARK: - Setup

    /// Ensures cache directory exists and loads metadata.
    private func ensureSetup() async throws {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        // Load metadata index if empty
        if metadataIndex.isEmpty {
            try await loadMetadataIndex()
        }
    }

    /// Loads metadata from disk into memory index.
    private func loadMetadataIndex() async throws {
        let indexURL = metadataIndexURL
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: indexURL)
            metadataIndex = try decoder.decode([String: CacheMetadata].self, from: data)

            // Calculate current size
            currentSizeBytes = metadataIndex.values.reduce(0) { $0 + $1.sizeBytes }

            // Prune expired entries
            await pruneExpired()
        } catch {
            // If index is corrupted, start fresh
            metadataIndex = [:]
            currentSizeBytes = 0
        }
    }

    /// Saves metadata index to disk.
    private func saveMetadataIndex() throws {
        let data = try encoder.encode(metadataIndex)
        try data.write(to: metadataIndexURL)
    }

    /// URL for the metadata index file.
    private var metadataIndexURL: URL {
        cacheDirectory.appendingPathComponent("_index.plist")
    }

    // MARK: - MediaCache Implementation

    public func store<T: Codable & Sendable>(_ data: T, for key: MediaCacheKey) async throws {
        try await ensureSetup()

        // Encode data
        let encodedData: Data
        do {
            encodedData = try encoder.encode(data)
        } catch {
            throw MediaCacheError.encodingFailed(error)
        }

        let codableKey = CodableCacheKey(from: key)
        let filename = codableKey.filename
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        // Evict if necessary to make room
        while currentSizeBytes + encodedData.count > maxSizeBytes && !metadataIndex.isEmpty {
            await evictLRU()
        }

        // Remove existing entry for this key
        if let existing = metadataIndex[filename] {
            currentSizeBytes -= existing.sizeBytes
        }

        // Write data to disk
        do {
            try encodedData.write(to: fileURL)
        } catch {
            throw MediaCacheError.ioError(error)
        }

        // Update metadata
        let metadata = CacheMetadata(
            key: codableKey,
            createdAt: Date(),
            accessedAt: Date(),
            sizeBytes: encodedData.count,
            dataTypeName: String(describing: T.self)
        )
        metadataIndex[filename] = metadata
        currentSizeBytes += encodedData.count

        // Save metadata index
        try saveMetadataIndex()
    }

    public func retrieve<T: Codable & Sendable>(_ type: T.Type, for key: MediaCacheKey) async throws -> T? {
        try await ensureSetup()

        let codableKey = CodableCacheKey(from: key)
        let filename = codableKey.filename
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        guard var metadata = metadataIndex[filename] else {
            missCount += 1
            return nil
        }

        // Check expiration
        if Date().timeIntervalSince(metadata.createdAt) > maxAge {
            await remove(for: key)
            missCount += 1
            return nil
        }

        // Check if file exists
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // File missing but metadata exists - clean up
            metadataIndex.removeValue(forKey: filename)
            try? saveMetadataIndex()
            missCount += 1
            return nil
        }

        hitCount += 1

        // Update access time
        metadata.markAccessed()
        metadataIndex[filename] = metadata
        try? saveMetadataIndex()

        // Read and decode data
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(type, from: data)
        } catch {
            throw MediaCacheError.decodingFailed(error)
        }
    }

    public func remove(for key: MediaCacheKey) async {
        let codableKey = CodableCacheKey(from: key)
        let filename = codableKey.filename
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        if let metadata = metadataIndex[filename] {
            currentSizeBytes -= metadata.sizeBytes
        }
        metadataIndex.removeValue(forKey: filename)

        try? fileManager.removeItem(at: fileURL)
        try? saveMetadataIndex()
    }

    public func removeAll(for mediaID: MediaID) async {
        let hashPrefix = mediaID.hashValue.description
        let keysToRemove = metadataIndex.keys.filter { $0.hasPrefix(hashPrefix) }

        for filename in keysToRemove {
            if let metadata = metadataIndex[filename] {
                currentSizeBytes -= metadata.sizeBytes
            }
            metadataIndex.removeValue(forKey: filename)

            let fileURL = cacheDirectory.appendingPathComponent(filename)
            try? fileManager.removeItem(at: fileURL)
        }

        try? saveMetadataIndex()
    }

    public func clear() async {
        metadataIndex.removeAll()
        currentSizeBytes = 0
        hitCount = 0
        missCount = 0

        // Remove all cache files
        if let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    public func contains(_ key: MediaCacheKey) async -> Bool {
        let codableKey = CodableCacheKey(from: key)
        let filename = codableKey.filename

        guard let metadata = metadataIndex[filename] else {
            return false
        }

        if Date().timeIntervalSince(metadata.createdAt) > maxAge {
            return false
        }

        let fileURL = cacheDirectory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    public func statistics() async -> CacheStatistics {
        CacheStatistics(
            entryCount: metadataIndex.count,
            memoryUsageBytes: currentSizeBytes,
            hitCount: hitCount,
            missCount: missCount
        )
    }

    // MARK: - Eviction

    /// Evicts the least recently used entry.
    ///
    /// - Complexity: O(n) where n is the number of cached entries.
    ///   Uses linear search to find minimum `accessedAt` timestamp.
    ///   See class documentation for trade-off analysis and optimization paths.
    private func evictLRU() async {
        guard let lruEntry = metadataIndex.min(by: { $0.value.accessedAt < $1.value.accessedAt }) else {
            return
        }

        let filename = lruEntry.key
        currentSizeBytes -= lruEntry.value.sizeBytes
        metadataIndex.removeValue(forKey: filename)

        let fileURL = cacheDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: fileURL)
    }

    /// Prunes expired entries.
    public func pruneExpired() async {
        let now = Date()
        let expiredKeys = metadataIndex.compactMap { (filename, metadata) -> String? in
            now.timeIntervalSince(metadata.createdAt) > maxAge ? filename : nil
        }

        for filename in expiredKeys {
            if let metadata = metadataIndex[filename] {
                currentSizeBytes -= metadata.sizeBytes
            }
            metadataIndex.removeValue(forKey: filename)

            let fileURL = cacheDirectory.appendingPathComponent(filename)
            try? fileManager.removeItem(at: fileURL)
        }

        if !expiredKeys.isEmpty {
            try? saveMetadataIndex()
        }
    }

    // MARK: - Convenience

    /// Gets current cache size in bytes.
    public var sizeBytes: Int {
        currentSizeBytes
    }

    /// Gets cache usage as a percentage.
    public var usagePercent: Double {
        Double(currentSizeBytes) / Double(maxSizeBytes)
    }
}

// MARK: - Shared Instance

extension DiskMediaCache {
    /// Shared disk cache instance with default settings.
    public static let shared = DiskMediaCache(maxSizeBytes: 500_000_000, maxAge: 604800)
}
