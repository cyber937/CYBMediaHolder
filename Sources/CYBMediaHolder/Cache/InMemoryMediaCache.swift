//
//  InMemoryMediaCache.swift
//  CYBMediaHolder
//
//  In-memory implementation of MediaCache.
//  Fast access, volatile (cleared on app termination).
//

import Foundation

/// In-memory cache implementation.
///
/// Provides fast cache access using a dictionary-based store.
/// All data is lost when the app terminates.
///
/// ## Features
/// - Fast O(1) access and LRU updates
/// - Automatic expiration (configurable)
/// - Memory limit with LRU eviction
/// - Thread-safe via actor isolation
/// - Zero-copy storage (no serialization overhead)
///
/// ## Usage
/// ```swift
/// let cache = InMemoryMediaCache(maxEntries: 100)
/// try await cache.store(waveform, for: key)
/// let cached = try await cache.retrieve(WaveformData.self, for: key)
/// ```
///
/// ## Design Notes
/// Unlike `DiskMediaCache`, this implementation stores values directly without
/// JSON serialization for better performance. Values are type-erased using
/// `any Sendable` and type-checked on retrieval.
///
/// ### LRUNode Thread Safety
/// `LRUNode` is a reference type used internally for O(1) LRU operations.
/// It is safe because:
/// - All nodes are created and managed exclusively within this actor
/// - Node references never escape the actor boundary
/// - External API only accepts/returns `Sendable` value types
public actor InMemoryMediaCache: MediaCache {

    // MARK: - Doubly Linked List Node

    /// Node for doubly linked list (O(1) removal and insertion).
    ///
    /// - Important: This class is intentionally a reference type for efficient
    ///   linked list operations. It must never be exposed outside the actor.
    private final class LRUNode {
        let key: MediaCacheKey
        var prev: LRUNode?
        var next: LRUNode?

        init(key: MediaCacheKey) {
            self.key = key
        }
    }

    // MARK: - Types

    /// Type-erased wrapper for cached values.
    ///
    /// Stores values directly without serialization for optimal performance.
    /// Type safety is ensured at retrieval time via dynamic casting.
    private struct CacheEntry {
        /// The cached value (type-erased for heterogeneous storage).
        let value: any Sendable

        /// Original type name for debugging/logging.
        let typeName: String

        /// When the entry was created.
        let createdAt: Date

        /// When the entry was last accessed.
        var accessedAt: Date

        /// Estimated memory size in bytes (for statistics).
        let estimatedSizeBytes: Int

        func withAccess() -> CacheEntry {
            var copy = self
            copy.accessedAt = Date()
            return copy
        }

        func isExpired(maxAge: TimeInterval) -> Bool {
            Date().timeIntervalSince(createdAt) > maxAge
        }
    }

    // MARK: - Properties

    /// Maximum number of entries.
    private let maxEntries: Int

    /// Maximum age of entries in seconds.
    private let maxAge: TimeInterval

    /// Cache storage.
    private var storage: [MediaCacheKey: CacheEntry] = [:]

    /// Node lookup for O(1) access to linked list nodes.
    private var nodeMap: [MediaCacheKey: LRUNode] = [:]

    /// Head of LRU list (least recently used).
    private var lruHead: LRUNode?

    /// Tail of LRU list (most recently used).
    private var lruTail: LRUNode?

    /// Statistics.
    private var hitCount = 0
    private var missCount = 0

    // MARK: - Initialization

    /// Creates an in-memory cache.
    ///
    /// - Parameters:
    ///   - maxEntries: Maximum number of entries (default: 100).
    ///   - maxAge: Maximum age in seconds (default: 1 hour).
    public init(maxEntries: Int = 100, maxAge: TimeInterval = 3600) {
        self.maxEntries = maxEntries
        self.maxAge = maxAge
    }

    // MARK: - LRU List Operations (O(1))

    /// Removes a node from the linked list (O(1)).
    private func removeNode(_ node: LRUNode) {
        let prev = node.prev
        let next = node.next

        if let prev = prev {
            prev.next = next
        } else {
            lruHead = next
        }

        if let next = next {
            next.prev = prev
        } else {
            lruTail = prev
        }

        node.prev = nil
        node.next = nil
    }

    /// Adds a node to the tail (most recently used) - O(1).
    private func addToTail(_ node: LRUNode) {
        if let tail = lruTail {
            tail.next = node
            node.prev = tail
            node.next = nil
            lruTail = node
        } else {
            // Empty list
            lruHead = node
            lruTail = node
            node.prev = nil
            node.next = nil
        }
    }

    /// Moves a node to tail (mark as recently used) - O(1).
    private func moveToTail(_ node: LRUNode) {
        if node === lruTail {
            return // Already at tail
        }
        removeNode(node)
        addToTail(node)
    }

    /// Removes the head node (least recently used) - O(1).
    private func removeHead() -> MediaCacheKey? {
        guard let head = lruHead else { return nil }
        let key = head.key
        removeNode(head)
        nodeMap.removeValue(forKey: key)
        return key
    }

    // MARK: - MediaCache Implementation

    public func store<T: Codable & Sendable>(_ data: T, for key: MediaCacheKey) async throws {
        // Remove existing entry if present
        if let existingNode = nodeMap[key] {
            removeNode(existingNode)
            nodeMap.removeValue(forKey: key)
            storage.removeValue(forKey: key)
        }

        // Evict if necessary
        while storage.count >= maxEntries {
            if let evictedKey = removeHead() {
                storage.removeValue(forKey: evictedKey)
            } else {
                break
            }
        }

        // Estimate memory size (rough approximation for statistics)
        let estimatedSize = MemoryLayout<T>.size(ofValue: data)

        // Store entry directly without serialization
        let entry = CacheEntry(
            value: data,
            typeName: String(describing: T.self),
            createdAt: Date(),
            accessedAt: Date(),
            estimatedSizeBytes: estimatedSize
        )
        storage[key] = entry

        // Add to LRU list
        let node = LRUNode(key: key)
        nodeMap[key] = node
        addToTail(node)
    }

    public func retrieve<T: Codable & Sendable>(_ type: T.Type, for key: MediaCacheKey) async throws -> T? {
        guard var entry = storage[key], let node = nodeMap[key] else {
            missCount += 1
            return nil
        }

        // Check expiration
        if entry.isExpired(maxAge: maxAge) {
            storage.removeValue(forKey: key)
            removeNode(node)
            nodeMap.removeValue(forKey: key)
            missCount += 1
            return nil
        }

        hitCount += 1

        // Update access time and move to tail (O(1))
        entry = entry.withAccess()
        storage[key] = entry
        moveToTail(node)

        // Type-safe cast (no decoding needed)
        guard let typedValue = entry.value as? T else {
            // Type mismatch - this shouldn't happen in normal usage
            throw MediaCacheError.decodingFailed(
                NSError(
                    domain: "InMemoryMediaCache",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Type mismatch: expected \(T.self), found \(entry.typeName)"
                    ]
                )
            )
        }

        return typedValue
    }

    public func remove(for key: MediaCacheKey) async {
        storage.removeValue(forKey: key)
        if let node = nodeMap[key] {
            removeNode(node)
            nodeMap.removeValue(forKey: key)
        }
    }

    public func removeAll(for mediaID: MediaID) async {
        let keysToRemove = storage.keys.filter { $0.mediaID == mediaID }
        for key in keysToRemove {
            storage.removeValue(forKey: key)
            if let node = nodeMap[key] {
                removeNode(node)
                nodeMap.removeValue(forKey: key)
            }
        }
    }

    public func clear() async {
        storage.removeAll()
        nodeMap.removeAll()
        lruHead = nil
        lruTail = nil
        hitCount = 0
        missCount = 0
    }

    public func contains(_ key: MediaCacheKey) async -> Bool {
        guard let entry = storage[key] else {
            return false
        }
        return !entry.isExpired(maxAge: maxAge)
    }

    public func statistics() async -> CacheStatistics {
        let memoryUsage = storage.values.reduce(0) { $0 + $1.estimatedSizeBytes }
        return CacheStatistics(
            entryCount: storage.count,
            memoryUsageBytes: memoryUsage,
            hitCount: hitCount,
            missCount: missCount
        )
    }

    // MARK: - Convenience Methods

    /// Prunes expired entries.
    public func pruneExpired() async {
        let expiredKeys = storage.compactMap { (key, entry) -> MediaCacheKey? in
            entry.isExpired(maxAge: maxAge) ? key : nil
        }
        for key in expiredKeys {
            storage.removeValue(forKey: key)
            if let node = nodeMap[key] {
                removeNode(node)
                nodeMap.removeValue(forKey: key)
            }
        }
    }

    /// Gets all keys in the cache.
    public var keys: [MediaCacheKey] {
        Array(storage.keys)
    }
}

// MARK: - Shared Instance

extension InMemoryMediaCache {
    /// Shared in-memory cache instance.
    public static let shared = InMemoryMediaCache(maxEntries: 200, maxAge: 7200)
}
