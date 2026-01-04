//
//  CYBMediaHolder.swift
//  CYBMediaHolder
//
//  Main export file for the CYBMediaHolder package.
//  Re-exports all public types for convenient import.
//

import Foundation

// MARK: - Package Information

/// CYBMediaHolder package version.
public let CYBMediaHolderVersion = "0.1.0"

/// CYBMediaHolder package description.
public let CYBMediaHolderDescription = """
CYBMediaHolder - Media holder framework for macOS/iOS.

A player-independent, extensible framework for managing media metadata,
analysis, and caching. Designed for professional media applications.

Features:
- Player-agnostic media representation
- Pluggable backends (AVFoundation, FFmpeg, RAW SDKs)
- Analysis services (waveform, peak, keyframe indexing)
- Capability-based feature detection
- Thread-safe actor-based design
"""

// MARK: - Quick Start

/*
 Quick Start Guide:

 1. Create a MediaHolder from a URL:

    let holder = try await MediaHolder.create(from: fileURL)

 2. Access media information:

    print(holder.descriptor.duration)
    print(holder.descriptor.videoSize)
    print(holder.isHDR)

 3. Check capabilities:

    let caps = await holder.capabilities
    if caps.contains(.waveformGeneratable) {
        // Can generate waveform
    }

 4. Generate analysis:

    let waveform = try await MediaAnalysisService.shared.generateWaveform(for: holder)

 5. Use with your player:

    let resolved = try await holder.locator.resolve()
    defer { resolved.stopAccessing() }
    let asset = AVAsset(url: resolved.url)
    // Create player item from asset...

 See README_Migration.md for detailed migration guide from CYBMedia.
*/

// MARK: - Type Re-exports

// Core Types
// - MediaID: Stable identifier for media
// - MediaLocator: Location abstraction (file, bookmark, remote)
// - MediaDescriptor: Immutable media properties
// - MediaStore: Mutable analysis/cache storage (actor)
// - MediaHolder: Central media representation
// - Capability: Feature availability flags

// Track Descriptors
// - VideoTrackDescriptor: Video track properties
// - AudioTrackDescriptor: Audio track properties
// - CodecInfo: Codec identification
// - ColorInfo: Color space metadata

// Services
// - MediaProbe: Protocol for probing backends
// - AVFoundationMediaProbe: AVFoundation implementation
// - MediaProbeRegistry: Probe management
// - MediaAnalysisService: Analysis orchestration

// Analysis Types
// - WaveformData: Audio waveform
// - PeakData: Audio peak levels
// - KeyframeIndex: Video keyframes
// - ThumbnailIndex: Thumbnail cache

// Cache
// - MediaCache: Cache protocol
// - InMemoryMediaCache: Memory cache implementation

// Migration
// - MediaMigrationService: CYBMedia migration
// - MediaHolderFactory: Convenience creation

// MARK: - Example Usage

#if DEBUG
/// Example demonstrating basic MediaHolder usage.
///
/// This is compiled only in DEBUG builds for documentation purposes.
@available(macOS 13.0, iOS 16.0, *)
enum MediaHolderExamples {

    /// Basic media loading example.
    static func basicUsage() async throws {
        // Create holder from URL
        let url = URL(fileURLWithPath: "/path/to/video.mov")
        let holder = try await MediaHolder.create(from: url)

        // Access descriptor
        print("Duration: \(holder.duration) seconds")
        print("Video size: \(holder.videoSize ?? .zero)")
        print("Frame rate: \(holder.frameRate ?? 0) fps")
        print("Is HDR: \(holder.isHDR)")

        // Check capabilities
        let caps = await holder.capabilities
        print("Capabilities: \(caps)")
    }

    /// Analysis generation example.
    static func analysisExample() async throws {
        let url = URL(fileURLWithPath: "/path/to/video.mov")
        let holder = try await MediaHolder.create(from: url)

        // Generate waveform with progress
        let waveform = try await MediaAnalysisService.shared.generateWaveform(
            for: holder,
            samplesPerSecond: 50
        ) { progress in
            print("Waveform progress: \(Int(progress * 100))%")
        }

        print("Waveform samples: \(waveform.count)")

        // Generate keyframe index
        let keyframes = try await MediaAnalysisService.shared.generateKeyframeIndex(
            for: holder
        )

        print("Keyframes found: \(keyframes.times.count)")
    }

    /// Security-scoped access example.
    static func securityScopedExample() async throws {
        let url = URL(fileURLWithPath: "/path/to/video.mov")

        // Create with security-scoped bookmark
        let holder = try await MediaHolder.createSecurityScoped(from: url)

        // Resolve for access
        let resolved = try await holder.locator.resolve()
        defer { resolved.stopAccessing() }

        // Use resolved.url with AVAsset, etc.
        print("Resolved URL: \(resolved.url)")
    }

    /// Migration from CYBMedia example.
    static func migrationExample() async throws {
        // Assuming you have a CYBVideo instance
        // let cybVideo: CYBVideo = ...

        // Create migration context
        let context = CYBMediaMigrationContext(
            originalID: UUID(), // cybVideo.id
            filePath: "/path/to/video.mov", // cybVideo.filePath
            name: "My Video", // cybVideo.name
            bookmark: nil, // cybVideo.bookmark
            wasOffline: false, // cybVideo.isOffline
            contentTypeIdentifier: "public.movie" // cybVideo.contentType?.identifier
        )

        // Migrate
        let holder = try await MediaMigrationService.shared.migrate(from: context)
        print("Migrated: \(holder.displayName)")
    }
}
#endif
