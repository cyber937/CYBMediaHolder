//
//  CoreNormalizedStore.swift
//  CYBMediaHolder
//
//  Storage container for core/* normalized metadata.
//  Manages resolved values and candidate tracking.
//

import Foundation

/// Storage container for core/* normalized metadata.
///
/// `CoreNormalizedStore` provides:
/// - Type-safe storage for all `CoreKey` values
/// - Multi-source candidate tracking with provenance
/// - Resolution of "winning" value from candidates
///
/// ## Design Notes
/// - Immutable by default; use `mutating` methods for modifications
/// - First candidate becomes resolved value (simple resolution)
/// - All candidates are preserved for audit/debugging
///
/// ## Usage
/// ```swift
/// var store = CoreNormalizedStore()
/// store.addCandidate(.videoWidth, CoreCandidate(value: .int(1920), source: "avfoundation"))
/// store.addCandidate(.videoHeight, CoreCandidate(value: .int(1080), source: "avfoundation"))
///
/// if let width = store.resolvedValue(.videoWidth)?.intValue {
///     print("Width: \(width)")
/// }
/// ```
///
/// ## Future Extensions
/// - Custom resolution strategies (confidence-based, priority-based)
/// - Bulk import from external sources
/// - CBOR/MessagePack serialization for persistence
public struct CoreNormalizedStore: Sendable, Equatable, Codable {

    /// Internal storage for all normalized values.
    private(set) public var values: [CoreKey: CoreNormalizedValue]

    /// Creates an empty store.
    public init() {
        self.values = [:]
    }

    /// Creates a store with pre-populated values.
    ///
    /// - Parameter values: Dictionary of keys to normalized values.
    public init(values: [CoreKey: CoreNormalizedValue]) {
        self.values = values
    }

    // MARK: - Adding Candidates

    /// Adds a candidate value for a key.
    ///
    /// If no resolved value exists, the first candidate becomes the resolved value.
    ///
    /// - Parameters:
    ///   - key: The core key.
    ///   - candidate: The candidate value with provenance.
    public mutating func addCandidate(_ key: CoreKey, _ candidate: CoreCandidate) {
        var entry = values[key] ?? CoreNormalizedValue()
        entry.candidates.append(candidate)

        // First candidate becomes resolved value (simple resolution)
        if entry.resolved == nil {
            entry.resolved = candidate.value
        }

        values[key] = entry
    }

    /// Adds a candidate value with inline parameters.
    ///
    /// - Parameters:
    ///   - key: The core key.
    ///   - value: The candidate value.
    ///   - source: Source identifier.
    ///   - confidence: Optional confidence score.
    public mutating func addCandidate(
        _ key: CoreKey,
        value: CoreValue,
        source: String,
        confidence: Double? = nil
    ) {
        let candidate = CoreCandidate(
            value: value,
            provenance: CoreProvenance(source: source, confidence: confidence)
        )
        addCandidate(key, candidate)
    }

    // MARK: - Resolution

    /// Sets the resolved value for a key, overriding automatic resolution.
    ///
    /// - Parameters:
    ///   - key: The core key.
    ///   - value: The resolved value (or nil to clear).
    public mutating func setResolved(_ key: CoreKey, _ value: CoreValue?) {
        var entry = values[key] ?? CoreNormalizedValue()
        entry.resolved = value
        values[key] = entry
    }

    /// Re-resolves a key using the highest confidence candidate.
    ///
    /// - Parameter key: The core key to resolve.
    /// - Returns: The newly resolved value, or nil if no candidates exist.
    @discardableResult
    public mutating func resolveByConfidence(_ key: CoreKey) -> CoreValue? {
        guard var entry = values[key], !entry.candidates.isEmpty else {
            return nil
        }

        // Find candidate with highest confidence (nil treated as 0)
        let best = entry.candidates.max { lhs, rhs in
            (lhs.provenance.confidence ?? 0) < (rhs.provenance.confidence ?? 0)
        }

        entry.resolved = best?.value
        values[key] = entry
        return entry.resolved
    }

    // MARK: - Retrieval

    /// Gets the resolved value for a key.
    ///
    /// - Parameter key: The core key.
    /// - Returns: The resolved value, or nil if not set.
    public func resolvedValue(_ key: CoreKey) -> CoreValue? {
        values[key]?.resolved
    }

    /// Gets all candidates for a key.
    ///
    /// - Parameter key: The core key.
    /// - Returns: Array of candidates (empty if none).
    public func candidates(_ key: CoreKey) -> [CoreCandidate] {
        values[key]?.candidates ?? []
    }

    /// Gets the full normalized value entry for a key.
    ///
    /// - Parameter key: The core key.
    /// - Returns: The normalized value entry, or nil if not present.
    public func normalizedValue(_ key: CoreKey) -> CoreNormalizedValue? {
        values[key]
    }

    /// Whether the store contains a value for a key.
    ///
    /// - Parameter key: The core key.
    /// - Returns: True if at least one candidate exists.
    public func contains(_ key: CoreKey) -> Bool {
        values[key]?.hasCandidates ?? false
    }

    // MARK: - Typed Retrieval

    /// Gets the resolved value as Int.
    public func intValue(_ key: CoreKey) -> Int? {
        resolvedValue(key)?.intValue
    }

    /// Gets the resolved value as Int64.
    public func int64Value(_ key: CoreKey) -> Int64? {
        resolvedValue(key)?.int64Value
    }

    /// Gets the resolved value as Double.
    public func doubleValue(_ key: CoreKey) -> Double? {
        resolvedValue(key)?.doubleValue
    }

    /// Gets the resolved value as Bool.
    public func boolValue(_ key: CoreKey) -> Bool? {
        resolvedValue(key)?.boolValue
    }

    /// Gets the resolved value as String.
    public func stringValue(_ key: CoreKey) -> String? {
        resolvedValue(key)?.stringValue
    }

    // MARK: - Bulk Operations

    /// All keys that have values in this store.
    public var allKeys: [CoreKey] {
        Array(values.keys)
    }

    /// Number of keys with values.
    public var count: Int {
        values.count
    }

    /// Whether the store is empty.
    public var isEmpty: Bool {
        values.isEmpty
    }

    /// Keys that have conflicting candidates.
    public var keysWithConflicts: [CoreKey] {
        values.compactMap { key, value in
            value.hasConflicts ? key : nil
        }
    }

    /// Merges another store into this one.
    ///
    /// Candidates from the other store are appended to existing keys.
    /// Resolution is not re-evaluated; existing resolved values are kept.
    ///
    /// - Parameter other: The store to merge from.
    public mutating func merge(_ other: CoreNormalizedStore) {
        for (key, otherValue) in other.values {
            for candidate in otherValue.candidates {
                addCandidate(key, candidate)
            }
        }
    }

    /// Removes a key and all its values.
    ///
    /// - Parameter key: The core key to remove.
    /// - Returns: The removed value, if any.
    @discardableResult
    public mutating func removeValue(forKey key: CoreKey) -> CoreNormalizedValue? {
        values.removeValue(forKey: key)
    }

    /// Removes all values from the store.
    public mutating func removeAll() {
        values.removeAll()
    }
}

// MARK: - CustomStringConvertible

extension CoreNormalizedStore: CustomStringConvertible {
    public var description: String {
        if isEmpty {
            return "CoreNormalizedStore(empty)"
        }

        let keyDescriptions = values.map { key, value in
            "  \(key.rawValue): \(value)"
        }.sorted()

        return "CoreNormalizedStore(\(count) keys):\n" + keyDescriptions.joined(separator: "\n")
    }
}

// MARK: - Subscript Access

extension CoreNormalizedStore {

    /// Subscript access to resolved values.
    public subscript(key: CoreKey) -> CoreValue? {
        get { resolvedValue(key) }
        set {
            if let value = newValue {
                setResolved(key, value)
            } else {
                _ = removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Custom Codable Implementation

extension CoreNormalizedStore {

    /// Wrapper for encoding/decoding CoreKey as string keys.
    private struct CodableEntry: Codable {
        let key: String
        let value: CoreNormalizedValue

        init(key: CoreKey, value: CoreNormalizedValue) {
            self.key = key.rawValue
            self.value = value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let entries = try container.decode([CodableEntry].self)

        var values: [CoreKey: CoreNormalizedValue] = [:]
        for entry in entries {
            if let key = CoreKey(rawValue: entry.key) {
                values[key] = entry.value
            }
            // Silently ignore unknown keys for forward compatibility
        }
        self.values = values
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let entries = values.map { CodableEntry(key: $0.key, value: $0.value) }
        try container.encode(entries)
    }
}
