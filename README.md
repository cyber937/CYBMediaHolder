# CYBMediaHolder

Backend-agnostic media metadata & analysis framework for Swift.

CYBMediaHolder manages the **authoritative facts of media assets** independently from UI, Player, or Decoder implementations. Designed for professional media workflows requiring stable identity, reliable metadata, and reusable analysis.

## Features

- **Stable Media Identity** - Path-independent identification for asset tracking
- **Immutable Metadata** - Duration, tracks, color space, HDR, timecode
- **Analysis Engine** - Waveform, peak, keyframe indexing with parallel execution
- **Hierarchical Cache** - L1 (memory) + L2 (disk) with automatic promotion
- **File Validation** - Magic number detection, symlink protection, path safety
- **Color Management** - BT.709, BT.2020, HLG, PQ, P3 support
- **Capability-Driven** - Feature flags for UI branching

## Requirements

- macOS 13+ / iOS 16+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/cyber937/CYBMediaHolder.git", from: "0.1.0")
]
```

## Quick Start

### Create a MediaHolder

```swift
import CYBMediaHolder

// From file URL
let holder = try await MediaHolder.create(from: fileURL)

// With macOS sandbox support
let holder = try await MediaHolder.createSecurityScoped(from: fileURL)
```

### Access Metadata

```swift
print(holder.duration)                    // Duration in seconds
print(holder.descriptor.frameRate)        // Frame rate
print(holder.descriptor.isHDR)            // HDR detection
print(holder.getTimecodeStart())          // Start timecode (if available)
```

### Check Capabilities

```swift
let caps = await holder.capabilities

if caps.contains(.waveformGeneratable) {
    showWaveformButton()
}

if caps.contains(.timecodeAvailable) {
    showTimecodeDisplay()
}
```

### Run Analysis

```swift
// Single analysis
let waveform = try await MediaAnalysisService.shared.generateWaveform(
    for: holder,
    samplesPerSecond: 100
)

// Parallel analysis (55% faster)
let result = try await MediaAnalysisService.shared.generateAllAnalysis(for: holder)
```

### Player Integration

```swift
let resolved = try await holder.locator.resolve()
defer { resolved.stopAccessing() }

let asset = AVAsset(url: resolved.url)
// Use asset with your player
```

## Architecture

```text
MediaHolder
├─ MediaID          (stable identity)
├─ MediaLocator     (location abstraction)
├─ MediaDescriptor  (immutable metadata)
├─ MediaStore       (mutable state, actor-isolated)
└─ Capability       (feature flags)
```

## Documentation

Detailed documentation is available in the [doc/](doc/) folder:

- [Architecture](doc/ARCHITECTURE.md) - Design principles and structure
- [Core Types](doc/CORE_TYPES.md) - MediaID, MediaLocator, MediaDescriptor, Capability
- [API Guide](doc/API_GUIDE.md) - Usage examples
- [Analysis](doc/ANALYSIS.md) - Waveform, peak, keyframe analysis
- [Cache](doc/CACHE.md) - L1/L2 hierarchical caching
- [Color](doc/COLOR.md) - Color space and HDR handling
- [Validation](doc/VALIDATION.md) - File validation and security
- [Services](doc/SERVICES.md) - Probe system and analyzers
- [Timecode](doc/TIMECODE.md) - Timecode extraction and availability
- [Core Normalized](doc/CORE_NORMALIZED.md) - Vendor-independent metadata layer

## Philosophy

> Playback is transient. Media facts are permanent.

CYBMediaHolder intentionally knows nothing about:

- AVPlayer or playback lifecycle
- Metal rendering
- UI state or frameworks

## License

MIT License

## A reference application built on this core:
CYBMediaPlayer (macOS)
