//
//  PeakData.swift
//  CYBMediaHolder
//
//  Peak data for audio level metering and display.
//

import Foundation

/// Peak data for audio level display.
///
/// Contains peak amplitude values computed over fixed-size windows
/// of audio samples. Used for VU meters and level visualization.
///
/// ## Usage
/// ```swift
/// let peak = peakData.peaks[windowIndex]
/// // peak is in range 0.0 (silence) to 1.0 (full scale)
/// ```
public struct PeakData: Codable, Sendable {

    /// Window size in samples.
    public let windowSize: Int

    /// Peak values per window (0.0 to 1.0 range).
    public let peaks: [Float]

    /// Generation timestamp.
    public let generatedAt: Date

    /// Creates peak data with the specified parameters.
    ///
    /// - Parameters:
    ///   - windowSize: Number of audio samples per peak window.
    ///   - peaks: Peak amplitude values for each window.
    public init(windowSize: Int, peaks: [Float]) {
        self.windowSize = windowSize
        self.peaks = peaks
        self.generatedAt = Date()
    }
}
