//
//  KeyframeIndex.swift
//  CYBMediaHolder
//
//  Keyframe index for fast video seeking.
//

import Foundation

/// Keyframe index for fast seeking.
///
/// Contains pre-computed keyframe positions for efficient video navigation.
/// Keyframes (I-frames) are the only frames that can be decoded independently,
/// so knowing their positions enables fast seeking.
///
/// ## Usage
/// ```swift
/// // Find nearest keyframe before target time
/// if let keyframeTime = index.nearestKeyframeBefore(time: 10.5) {
///     // Seek to keyframeTime first, then decode forward to 10.5
/// }
/// ```
public struct KeyframeIndex: Codable, Sendable {

    /// Keyframe times in seconds.
    public let times: [Double]

    /// Keyframe frame numbers (if available).
    public let frameNumbers: [Int]?

    /// Generation timestamp.
    public let generatedAt: Date

    /// Creates a keyframe index with the specified parameters.
    ///
    /// - Parameters:
    ///   - times: Keyframe presentation times in seconds.
    ///   - frameNumbers: Optional frame numbers corresponding to each keyframe.
    public init(times: [Double], frameNumbers: [Int]? = nil) {
        self.times = times
        self.frameNumbers = frameNumbers
        self.generatedAt = Date()
    }

    /// Find nearest keyframe before the given time.
    ///
    /// - Parameter time: Target time in seconds.
    /// - Returns: Time of the nearest preceding keyframe, or nil if none exists.
    public func nearestKeyframeBefore(time: Double) -> Double? {
        times.last { $0 <= time }
    }

    /// Find nearest keyframe after the given time.
    ///
    /// - Parameter time: Target time in seconds.
    /// - Returns: Time of the nearest following keyframe, or nil if none exists.
    public func nearestKeyframeAfter(time: Double) -> Double? {
        times.first { $0 > time }
    }
}
