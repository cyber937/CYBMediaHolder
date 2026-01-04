//
//  CacheManager.swift
//  CYBMediaHolder
//
//  Unified cache orchestrator providing L1 (memory) + L2 (disk) hierarchical caching.
//  Manages cache coordination, promotion, and invalidation strategies.
//

import Foundation

/// Unified cache manager providing hierarchical L1/L2 caching.
///
/// `CacheManager` orchestrates between in-memory and disk caches to provide
/// optimal performance with persistence:
/// - **L1 (Memory)**: Fast access, limited capacity, volatile
/// - **L2 (Disk)**: Slower access, larger capacity, persistent
///
/// ## Cache Strategy
/// - **Write-through**: Data is written to both L1 and L2 on store
/// - **Read-through**: L2 hits are promoted to L1 for faster subsequent access
/// - **LRU eviction**: Both caches use LRU to manage capacity
///
/// ## Usage
/// ```swift
/// let cache = CacheManager.shared
///
/// // Store analysis data (writes to both L1 and L2)
/// try await cache.store(waveform, for: key)
///
/// // Retrieve (checks L1 first, then L2 with promotion)
/// if let cached = try await cache.retrieve(WaveformData.self, for: key) {
///     // Use cached data
/// }
/// ```
///
/// ## Thread Safety
/// Actor isolation ensures all operations are thread-safe.
///
/// ## Performance Characteristics
/// - L1 hit: ~1ms (memory access)
/// - L2 hit: ~10-50ms (disk I/O)
/// - L2 hit with promotion: subsequent access becomes L1 hit
public actor CacheManager {

    // MARK: - Shared Instance

    /// Shared cache manager with default configuration.
    public static let shared = CacheManager()

    // MARK: - Properties

    /// L1 in-memory cache (fast, volatile).
    private let memoryCache: InMemoryMediaCache

    /// L2 disk cache (persistent, larger capacity).
    private let diskCache: DiskMediaCache

    /// Configuration for cache behavior.
    private let configuration: Configuration

    /// Statistics tracking.
    private var l1Hits = 0
    private var l2Hits = 0
    private var misses = 0

    // MARK: - Configuration

    /// Configuration for cache manager behavior.
    public struct Configuration: Sendable {
        /// Whether to write to L2 (disk) on store operations.
        public let writeToL2: Bool

        /// Whether to promote L2 hits to L1.
        public let promoteL2Hits: Bool

        /// Whether to write to L2 asynchronously (non-blocking).
        public let asyncL2Writes: Bool

        /// Default configuration.
        public static let `default` = Configuration(
            writeToL2: true,
            promoteL2Hits: true,
            asyncL2Writes: true
        )

        /// Memory-only configuration (no disk persistence).
        public static let memoryOnly = Configuration(
            writeToL2: false,
            promoteL2Hits: false,
            asyncL2Writes: false
        )

        public init(
            writeToL2: Bool = true,
            promoteL2Hits: Bool = true,
            asyncL2Writes: Bool = true
        ) {
            self.writeToL2 = writeToL2
            self.promoteL2Hits = promoteL2Hits
            self.asyncL2Writes = asyncL2Writes
        }
    }

    // MARK: - Initialization

    /// Creates a cache manager with custom caches and configuration.
    ///
    /// - Parameters:
    ///   - memoryCache: The L1 in-memory cache.
    ///   - diskCache: The L2 disk cache.
    ///   - configuration: Cache behavior configuration.
    public init(
        memoryCache: InMemoryMediaCache = InMemoryMediaCache.shared,
        diskCache: DiskMediaCache = DiskMediaCache.shared,
        configuration: Configuration = .default
    ) {
        self.memoryCache = memoryCache
        self.diskCache = diskCache
        self.configuration = configuration
    }

    // MARK: - Cache Operations

    /// Stores data in the cache hierarchy.
    ///
    /// Data is written to L1 (memory) immediately. If configured, also writes
    /// to L2 (disk) synchronously or asynchronously.
    ///
    /// - Parameters:
    ///   - data: The data to cache.
    ///   - key: The cache key.
    /// - Throws: If encoding or storage fails.
    public func store<T: Codable & Sendable>(_ data: T, for key: MediaCacheKey) async throws {
        // Always write to L1
        try await memoryCache.store(data, for: key)

        // Optionally write to L2
        if configuration.writeToL2 {
            if configuration.asyncL2Writes {
                // Fire-and-forget L2 write for performance
                Task {
                    try? await diskCache.store(data, for: key)
                }
            } else {
                // Synchronous L2 write for data safety
                try await diskCache.store(data, for: key)
            }
        }
    }

    /// Retrieves data from the cache hierarchy.
    ///
    /// Checks L1 first for fast access. On L1 miss, checks L2 and optionally
    /// promotes the hit to L1 for faster subsequent access.
    ///
    /// - Parameters:
    ///   - type: The expected type of the cached data.
    ///   - key: The cache key.
    /// - Returns: The cached data, or nil if not found.
    /// - Throws: If decoding fails.
    public func retrieve<T: Codable & Sendable>(_ type: T.Type, for key: MediaCacheKey) async throws -> T? {
        // Check L1 first
        if let cached = try await memoryCache.retrieve(type, for: key) {
            l1Hits += 1
            return cached
        }

        // Check L2
        if let cached = try await diskCache.retrieve(type, for: key) {
            l2Hits += 1

            // Promote to L1 for faster future access
            if configuration.promoteL2Hits {
                try? await memoryCache.store(cached, for: key)
            }

            return cached
        }

        misses += 1
        return nil
    }

    /// Removes data from both cache levels.
    ///
    /// - Parameter key: The cache key.
    public func remove(for key: MediaCacheKey) async {
        await memoryCache.remove(for: key)
        await diskCache.remove(for: key)
    }

    /// Removes all cache entries for a media ID from both levels.
    ///
    /// - Parameter mediaID: The media ID.
    public func removeAll(for mediaID: MediaID) async {
        await memoryCache.removeAll(for: mediaID)
        await diskCache.removeAll(for: mediaID)
    }

    /// Clears all cache entries from both levels.
    public func clear() async {
        await memoryCache.clear()
        await diskCache.clear()
        l1Hits = 0
        l2Hits = 0
        misses = 0
    }

    /// Checks if a cache entry exists in either level.
    ///
    /// - Parameter key: The cache key.
    /// - Returns: True if the entry exists in L1 or L2.
    public func contains(_ key: MediaCacheKey) async -> Bool {
        if await memoryCache.contains(key) {
            return true
        }
        return await diskCache.contains(key)
    }

    // MARK: - Cache Management

    /// Warms up L1 cache from L2 for frequently accessed items.
    ///
    /// - Parameter keys: Keys to warm up.
    /// - Throws: If retrieval fails.
    public func warmUp<T: Codable & Sendable>(_ type: T.Type, for keys: [MediaCacheKey]) async throws {
        for key in keys {
            // Skip if already in L1
            if await memoryCache.contains(key) {
                continue
            }

            // Load from L2 into L1
            if let data = try await diskCache.retrieve(type, for: key) {
                try await memoryCache.store(data, for: key)
            }
        }
    }

    /// Flushes L1 cache to L2 (for persistence before app termination).
    ///
    /// Note: This is primarily useful when using memory-only configuration
    /// and you want to selectively persist some items.
    public func flushToL2() async {
        // L1 entries are already in L2 in write-through mode
        // This method is a no-op in default configuration
        // Could be extended to support write-behind caching in the future
    }

    // MARK: - Statistics

    /// Combined cache statistics from both levels.
    public func statistics() async -> CombinedCacheStatistics {
        let l1Stats = await memoryCache.statistics()
        let l2Stats = await diskCache.statistics()

        return CombinedCacheStatistics(
            l1: l1Stats,
            l2: l2Stats,
            l1HitCount: l1Hits,
            l2HitCount: l2Hits,
            missCount: misses
        )
    }
}

// MARK: - Combined Statistics

/// Combined statistics from both cache levels.
public struct CombinedCacheStatistics: Sendable {
    /// L1 (memory) cache statistics.
    public let l1: CacheStatistics

    /// L2 (disk) cache statistics.
    public let l2: CacheStatistics

    /// L1 hit count.
    public let l1HitCount: Int

    /// L2 hit count.
    public let l2HitCount: Int

    /// Total miss count.
    public let missCount: Int

    /// Total cache accesses.
    public var totalAccesses: Int {
        l1HitCount + l2HitCount + missCount
    }

    /// Overall hit rate (L1 + L2).
    public var hitRate: Double {
        guard totalAccesses > 0 else { return 0 }
        return Double(l1HitCount + l2HitCount) / Double(totalAccesses)
    }

    /// L1 hit rate (of total accesses).
    public var l1HitRate: Double {
        guard totalAccesses > 0 else { return 0 }
        return Double(l1HitCount) / Double(totalAccesses)
    }

    /// L2 hit rate (of L1 misses).
    public var l2HitRate: Double {
        let l1Misses = l2HitCount + missCount
        guard l1Misses > 0 else { return 0 }
        return Double(l2HitCount) / Double(l1Misses)
    }

    /// Total entry count across both levels.
    public var totalEntries: Int {
        l1.entryCount + l2.entryCount
    }

    /// Total memory usage (L1 + L2 estimate).
    public var totalMemoryBytes: Int {
        l1.memoryUsageBytes + l2.memoryUsageBytes
    }
}
