//
//  AnalysisState.swift
//  CYBMediaHolder
//
//  Aggregate state for all analysis data associated with a media item.
//

import Foundation

/// Analysis state containing all generated analysis data.
///
/// This struct aggregates optional references to various analysis outputs
/// (waveform, peaks, keyframes, thumbnails) for a media item.
///
/// ## Usage
/// ```swift
/// var state = AnalysisState()
/// state.waveform = generatedWaveform
/// state.keyframeIndex = generatedKeyframes
///
/// // Check what analysis is available
/// if state.waveform != nil {
///     // Render waveform UI
/// }
/// ```
public struct AnalysisState: Codable, Sendable {

    /// Waveform data for audio visualization.
    public var waveform: WaveformData?

    /// Peak data for audio level metering.
    public var peak: PeakData?

    /// Keyframe index for fast video seeking.
    public var keyframeIndex: KeyframeIndex?

    /// Thumbnail index for preview scrubbing.
    public var thumbnailIndex: ThumbnailIndex?

    /// Creates an analysis state with optional analysis data.
    ///
    /// - Parameters:
    ///   - waveform: Waveform visualization data.
    ///   - peak: Peak level data.
    ///   - keyframeIndex: Keyframe position index.
    ///   - thumbnailIndex: Thumbnail preview index.
    public init(
        waveform: WaveformData? = nil,
        peak: PeakData? = nil,
        keyframeIndex: KeyframeIndex? = nil,
        thumbnailIndex: ThumbnailIndex? = nil
    ) {
        self.waveform = waveform
        self.peak = peak
        self.keyframeIndex = keyframeIndex
        self.thumbnailIndex = thumbnailIndex
    }

    /// Whether any analysis data is present.
    public var hasAnyData: Bool {
        waveform != nil || peak != nil || keyframeIndex != nil || thumbnailIndex != nil
    }

    /// Whether all possible analysis data is present.
    public var isComplete: Bool {
        waveform != nil && peak != nil && keyframeIndex != nil && thumbnailIndex != nil
    }
}
