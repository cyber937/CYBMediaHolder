//
//  MockMediaCache.swift
//  CYBMediaHolderTests
//
//  Mock implementation of MediaCache for testing purposes.
//

import Foundation
@testable import CYBMediaHolder

/// Mock cache implementation for testing.
///
/// Tracks all cache operations and allows controlled behavior simulation.
public actor MockMediaCache: MediaCache {

    // MARK: - Properties

    /// Storage for cached items.
    private var storage: [String: (data: Data, type: String)] = [:]

    /// Track store operations.
    public private(set) var storeCount = 0

    /// Track retrieve operations.
    public private(set) var retrieveCount = 0

    /// Track remove operations.
    public private(set) var removeCount = 0

    /// Simulate failures when true.
    public var shouldFailOnStore = false
    public var shouldFailOnRetrieve = false

    /// Statistics tracking.
    private var hitCount = 0
    private var missCount = 0

    // MARK: - Initialization

    public init() {}

    // MARK: - MediaCache Implementation

    public func store<T: Codable & Sendable>(_ data: T, for key: MediaCacheKey) async throws {
        storeCount += 1

        if shouldFailOnStore {
            throw MediaCacheError.encodingFailed(NSError(domain: "MockCache", code: -1))
        }

        let keyString = makeKeyString(key)
        let encodedData = try JSONEncoder().encode(data)
        storage[keyString] = (data: encodedData, type: String(describing: T.self))
    }

    public func retrieve<T: Codable & Sendable>(_ type: T.Type, for key: MediaCacheKey) async throws -> T? {
        retrieveCount += 1

        if shouldFailOnRetrieve {
            throw MediaCacheError.decodingFailed(NSError(domain: "MockCache", code: -1))
        }

        let keyString = makeKeyString(key)
        guard let entry = storage[keyString] else {
            missCount += 1
            return nil
        }

        hitCount += 1
        return try JSONDecoder().decode(type, from: entry.data)
    }

    public func remove(for key: MediaCacheKey) async {
        removeCount += 1
        let keyString = makeKeyString(key)
        storage.removeValue(forKey: keyString)
    }

    public func removeAll(for mediaID: MediaID) async {
        let prefix = "\(mediaID.hashValue)"
        storage = storage.filter { !$0.key.hasPrefix(prefix) }
    }

    public func clear() async {
        storage.removeAll()
        hitCount = 0
        missCount = 0
    }

    public func contains(_ key: MediaCacheKey) async -> Bool {
        let keyString = makeKeyString(key)
        return storage[keyString] != nil
    }

    public func statistics() async -> CacheStatistics {
        CacheStatistics(
            entryCount: storage.count,
            memoryUsageBytes: storage.values.reduce(0) { $0 + $1.data.count },
            hitCount: hitCount,
            missCount: missCount
        )
    }

    // MARK: - Helpers

    private func makeKeyString(_ key: MediaCacheKey) -> String {
        let variant = key.variant ?? "default"
        return "\(key.mediaID.hashValue)_\(key.dataType.rawValue)_\(variant)"
    }

    // MARK: - Test Utilities

    /// Resets all tracking counters.
    public func reset() {
        storeCount = 0
        retrieveCount = 0
        removeCount = 0
        hitCount = 0
        missCount = 0
        storage.removeAll()
        shouldFailOnStore = false
        shouldFailOnRetrieve = false
    }

    /// Returns the current entry count.
    public var entryCount: Int {
        storage.count
    }
}
