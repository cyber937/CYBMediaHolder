//
//  CoreRecord.swift
//  CYBMediaHolder
//
//  Provenance tracking and candidate values for core/* normalization.
//  Enables multi-source metadata with confidence scoring.
//

import Foundation

/// Provenance information for a core/* value.
///
/// `CoreProvenance` tracks where a metadata value came from,
/// enabling conflict resolution and audit trails.
///
/// ## Design Notes
/// - `source`: Backend or plugin identifier (e.g., "avfoundation", "ffprobe")
/// - `confidence`: Optional quality score (0.0-1.0), nil if not applicable
///
/// ## Example Sources
/// - `"avfoundation"`: AVFoundation probe
/// - `"ffprobe"`: FFmpeg probe
/// - `"plugin:sony"`: Sony MXF plugin
/// - `"embedded:tmcd"`: Embedded timecode track
/// - `"filename"`: Parsed from filename
public struct CoreProvenance: Sendable, Equatable, Hashable, Codable {

    /// Source identifier (backend, plugin, or extraction method).
    public let source: String

    /// Optional confidence score (0.0 = low, 1.0 = high).
    /// Nil if confidence scoring is not applicable.
    public let confidence: Double?

    /// Creates a provenance with source and optional confidence.
    ///
    /// - Parameters:
    ///   - source: The source identifier.
    ///   - confidence: Optional confidence score (0.0-1.0).
    public init(source: String, confidence: Double? = nil) {
        self.source = source
        self.confidence = confidence
    }
}

// MARK: - Common Provenances

extension CoreProvenance {

    /// AVFoundation probe backend.
    public static let avfoundation = CoreProvenance(source: "avfoundation")

    /// FFmpeg probe backend (future).
    public static let ffprobe = CoreProvenance(source: "ffprobe")

    /// Unknown or unspecified source.
    public static let unknown = CoreProvenance(source: "unknown")
}

// MARK: - CustomStringConvertible

extension CoreProvenance: CustomStringConvertible {
    public var description: String {
        if let confidence = confidence {
            return "\(source) (conf: \(String(format: "%.2f", confidence)))"
        }
        return source
    }
}

// MARK: - CoreCandidate

/// A candidate value with its provenance.
///
/// `CoreCandidate` pairs a `CoreValue` with its `CoreProvenance`,
/// enabling multiple sources to contribute values for the same key.
///
/// ## Usage
/// ```swift
/// let candidate = CoreCandidate(
///     value: .string("01:00:00:00"),
///     provenance: CoreProvenance(source: "tmcd", confidence: 0.95)
/// )
/// ```
public struct CoreCandidate: Sendable, Equatable, Hashable, Codable {

    /// The candidate value.
    public let value: CoreValue

    /// Source and confidence information.
    public let provenance: CoreProvenance

    /// Creates a candidate with value and provenance.
    ///
    /// - Parameters:
    ///   - value: The candidate value.
    ///   - provenance: Source and confidence information.
    public init(value: CoreValue, provenance: CoreProvenance) {
        self.value = value
        self.provenance = provenance
    }
}

// MARK: - Convenience Initializers

extension CoreCandidate {

    /// Creates a candidate with value and source string.
    ///
    /// - Parameters:
    ///   - value: The candidate value.
    ///   - source: Source identifier string.
    ///   - confidence: Optional confidence score.
    public init(value: CoreValue, source: String, confidence: Double? = nil) {
        self.value = value
        self.provenance = CoreProvenance(source: source, confidence: confidence)
    }
}

// MARK: - CustomStringConvertible

extension CoreCandidate: CustomStringConvertible {
    public var description: String {
        "\(value) from \(provenance)"
    }
}

// MARK: - CoreNormalizedValue

/// Container for resolved value and all candidates.
///
/// `CoreNormalizedValue` holds:
/// - `resolved`: The "winner" value to use (may be nil if unresolved)
/// - `candidates`: All contributed values with their sources
///
/// ## Resolution Strategy
/// By default, the first candidate becomes the resolved value.
/// Future: Implement confidence-based or priority-based resolution.
public struct CoreNormalizedValue: Sendable, Equatable, Codable {

    /// The resolved (winning) value, if any.
    public var resolved: CoreValue?

    /// All candidate values with provenance.
    public var candidates: [CoreCandidate]

    /// Creates an empty normalized value.
    public init() {
        self.resolved = nil
        self.candidates = []
    }

    /// Creates a normalized value with resolved value and candidates.
    ///
    /// - Parameters:
    ///   - resolved: The resolved value.
    ///   - candidates: All candidate values.
    public init(resolved: CoreValue?, candidates: [CoreCandidate]) {
        self.resolved = resolved
        self.candidates = candidates
    }

    /// Whether this value has any candidates.
    public var hasCandidates: Bool {
        !candidates.isEmpty
    }

    /// Whether this value has been resolved.
    public var isResolved: Bool {
        resolved != nil
    }

    /// The number of candidates.
    public var candidateCount: Int {
        candidates.count
    }

    /// Whether there are conflicting candidates (different values).
    public var hasConflicts: Bool {
        guard candidates.count > 1 else { return false }
        let firstValue = candidates.first?.value
        return candidates.contains { $0.value != firstValue }
    }
}

// MARK: - CustomStringConvertible

extension CoreNormalizedValue: CustomStringConvertible {
    public var description: String {
        if let resolved = resolved {
            return "resolved: \(resolved) (\(candidates.count) candidates)"
        }
        return "unresolved (\(candidates.count) candidates)"
    }
}
