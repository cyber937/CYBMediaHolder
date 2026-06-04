//
//  WaveformData.swift
//  CYBMediaHolder
//
//  Waveform data for audio visualization.
//  Optimized for performance with contiguous arrays.
//

import Foundation

/// Waveform data for audio visualization.
///
/// Optimized for performance with contiguous arrays instead of nested arrays.
/// Each channel's min/max values are stored in separate flat arrays for
/// better cache locality during rendering.
///
/// ## Usage
/// ```swift
/// // Access samples by index
/// let (min, max) = waveform[100]
///
/// // Get sample count
/// let totalSamples = waveform.count
/// ```
public struct WaveformData: Codable, Sendable {

    /// Samples per second of the waveform.
    public let samplesPerSecond: Int

    /// Minimum sample values (contiguous array for cache efficiency).
    public let minSamples: [Float]

    /// Maximum sample values (contiguous array for cache efficiency).
    public let maxSamples: [Float]

    /// Channel count.
    public let channelCount: Int

    /// Generation timestamp.
    public let generatedAt: Date

    /// Number of waveform samples.
    public var count: Int { minSamples.count }

    /// Subscript access to min/max pair at given index.
    public subscript(index: Int) -> (min: Float, max: Float) {
        (minSamples[index], maxSamples[index])
    }

    /// Creates waveform data with the specified parameters.
    ///
    /// - Parameters:
    ///   - samplesPerSecond: Number of waveform samples per second of audio.
    ///   - minSamples: Minimum amplitude values for each sample window.
    ///   - maxSamples: Maximum amplitude values for each sample window.
    ///   - channelCount: Number of audio channels represented.
    public init(
        samplesPerSecond: Int,
        minSamples: [Float],
        maxSamples: [Float],
        channelCount: Int
    ) {
        // `count` and `subscript` assume the two arrays are parallel; enforce it
        // up front so a mismatch fails loudly at construction rather than as an
        // out-of-bounds trap during rendering.
        precondition(
            minSamples.count == maxSamples.count,
            "WaveformData requires minSamples and maxSamples to have equal counts (\(minSamples.count) != \(maxSamples.count))"
        )
        self.samplesPerSecond = samplesPerSecond
        self.minSamples = minSamples
        self.maxSamples = maxSamples
        self.channelCount = channelCount
        self.generatedAt = Date()
    }
}
