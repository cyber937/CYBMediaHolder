# CYBMedia → MediaHolder Migration Guide

This guide explains how to migrate from the existing `CYBMedia` package to the new `CYBMediaHolder` architecture.

## Overview

### Why Migrate?

The original `CYBMedia` was designed as a simple media wrapper. `CYBMediaHolder` provides:

| Feature | CYBMedia | CYBMediaHolder |
|---------|----------|----------------|
| Player Independence | ❌ Embedded AVPlayerItem | ✅ Player-agnostic |
| Backend Abstraction | ❌ AVFoundation only | ✅ Pluggable (AVF/FFmpeg/RAW) |
| Analysis Cache | ❌ None | ✅ Waveform/Peak/Keyframe |
| Remote Support | ❌ Local only | ✅ HTTP/S3 ready |
| Thread Safety | ❌ Struct mutations | ✅ Actor-based |

### Architecture Comparison

```
CYBMedia (Old)                    CYBMediaHolder (New)
─────────────────                 ────────────────────
CYBMedia protocol                 MediaHolder class
├── id: UUID                      ├── id: MediaID
├── filePath: String              ├── locator: MediaLocator
├── bookmark: Data?               ├── descriptor: MediaDescriptor
├── contentType: UTType?          ├── store: MediaStore (actor)
└── (+ player-specific props)     └── capabilities: Capability

CYBVideo struct                   Separation of Concerns:
├── asset: AVAsset               → (Probe responsibility)
├── videoTrack: AVAssetTrack     → (Probe responsibility)
├── playerItem: AVPlayerItem     → (Player responsibility)
├── duration, fps, ...           → MediaDescriptor
└── compositionInfo              → (Player responsibility)
```

## Migration Steps

### Step 1: Add CYBMediaHolder Dependency

In your `Package.swift`:

```swift
dependencies: [
    .package(path: "../CYBMediaHolder"),
    // Keep CYBMedia for now during transition
    .package(path: "../CYBMedia"),
]
```

### Step 2: Create MediaHolder from Existing CYBMedia

```swift
import CYBMedia
import CYBMediaHolder

// Old way
var cybVideo = try CYBVideo(url: fileURL)
try await cybVideo.findVideoInformation()

// New way - Direct creation
let holder = try await MediaHolder.create(from: fileURL)

// Or with security scoping
let holder = try await MediaHolder.createSecurityScoped(from: fileURL)

// Or via migration from existing CYBMedia
let context = CYBMediaMigrationContext(
    originalID: cybVideo.id,
    filePath: cybVideo.filePath,
    name: cybVideo.name,
    bookmark: cybVideo.bookmark,
    wasOffline: cybVideo.isOffline,
    contentTypeIdentifier: cybVideo.contentType?.identifier
)
let holder = try await MediaMigrationService.shared.migrate(from: context)
```

### Step 3: Access Media Properties

```swift
// Old way (CYBVideo)
let duration = cybVideo.duration
let fps = cybVideo.fps
let size = cybVideo.videoSize

// New way (MediaHolder)
let duration = holder.duration                    // Direct property
let fps = holder.descriptor.frameRate            // Via descriptor
let size = holder.descriptor.videoSize           // Via descriptor

// Or access full descriptor
let desc = holder.descriptor
print("Duration: \(desc.durationSeconds)s")
print("Video: \(desc.videoTracks.count) track(s)")
print("Audio: \(desc.audioTracks.count) track(s)")
print("HDR: \(desc.isHDR)")
```

### Step 4: Replace Player Integration

The key difference: `MediaHolder` does NOT manage playback.

```swift
// Old way - CYBVideo managed player item
try await cybVideo.setAVPlayerItem(videSize: screenSize)
let playerItem = cybVideo.playerItem

// New way - Player creates its own resources using descriptor
let holder = try await MediaHolder.create(from: fileURL)

// Resolve URL for player
let resolved = try await holder.locator.resolve()
defer { resolved.stopAccessing() }

// Player creates its own AVAsset/AVPlayerItem
let asset = AVAsset(url: resolved.url)
let playerItem = AVPlayerItem(asset: asset)
// Configure player item using descriptor info...
```

### Step 5: Use Analysis Services

```swift
// Generate waveform (new feature)
let waveform = try await MediaAnalysisService.shared.generateWaveform(
    for: holder,
    samplesPerSecond: 100
) { progress in
    print("Waveform: \(Int(progress * 100))%")
}

// Generate keyframe index for fast seeking
let keyframes = try await MediaAnalysisService.shared.generateKeyframeIndex(
    for: holder
)

// Access cached results
if let cached = await holder.getWaveform() {
    displayWaveform(cached)
}
```

### Step 6: Check Capabilities

```swift
// Check what operations are available
let caps = await holder.capabilities

if caps.contains(.waveformGeneratable) {
    showWaveformButton()
}

if caps.contains(.reversePlayback) {
    enableReversePlayback()
}

if caps.contains(.hdrMetadata) {
    showHDRIndicator()
}

// Quick sync check (without analysis state)
if holder.baseCapabilities.contains(.videoPlayback) {
    // Can play video
}
```

## Property Mapping Reference

| CYBVideo | MediaHolder |
|----------|-------------|
| `id` | `id.uuid` |
| `filePath` | `locator.filePath` |
| `name` | `displayName` |
| `bookmark` | `locator` (as `.securityScopedBookmark`) |
| `contentType` | `descriptor.container.uniformTypeIdentifier` |
| `duration` | `descriptor.durationSeconds` or `duration` |
| `fps` | `descriptor.frameRate` |
| `timescale` | `descriptor.timebase` |
| `videoSize` | `descriptor.videoSize` |
| `videoFormat` | `descriptor.primaryVideoTrack?.codec.fourCC` |
| `audioFormat` | `descriptor.primaryAudioTrack?.codec.fourCC` |
| `hasAudio` | `descriptor.hasAudio` |
| `totalFrameNumber` | `descriptor.estimatedFrameCount` |

### Removed Properties (Player Responsibility)

These properties are intentionally NOT in MediaHolder:

- `asset: AVAsset` → Player creates from locator
- `videoTrack: AVAssetTrack` → Player loads tracks
- `audioTrack: AVAssetTrack` → Player loads tracks
- `playerItem: AVPlayerItem` → Player creates
- `compositionInfo` → Player creates compositions

## Common Patterns

### Iterating Media Collection

```swift
// Old
var videos: [CYBVideo] = []
for url in urls {
    var video = try CYBVideo(url: url)
    try await video.findVideoInformation()
    videos.append(video)
}

// New
var holders: [MediaHolder] = []
for url in urls {
    let holder = try await MediaHolder.create(from: url)
    holders.append(holder)
}

// Or with async let for parallel loading
async let holder1 = MediaHolder.create(from: url1)
async let holder2 = MediaHolder.create(from: url2)
let holders = try await [holder1, holder2]
```

### Persisting Media References

```swift
// Old (Codable)
let data = try JSONEncoder().encode(cybVideo)
let restored = try JSONDecoder().decode(CYBVideo.self, from: data)

// New - Persist locator and recreate
struct MediaReference: Codable {
    let id: UUID
    let locator: MediaLocator
    let displayName: String
}

// Save
let ref = MediaReference(
    id: holder.id.uuid,
    locator: holder.locator,
    displayName: holder.displayName
)
let data = try JSONEncoder().encode(ref)

// Restore
let ref = try JSONDecoder().decode(MediaReference.self, from: data)
let holder = try await MediaHolder.create(from: ref.locator)
```

### Handling Offline State

```swift
// Old
if cybVideo.isOffline {
    try cybVideo.recoverFromOffline(url: newURL)
}

// New - Resolution handles offline detection
do {
    let resolved = try await holder.locator.resolve()
    // Use resolved.url
    resolved.stopAccessing()
} catch MediaLocator.ResolutionError.fileNotFound(let path) {
    // File is offline/moved
    showReconnectDialog(originalPath: path)
} catch MediaLocator.ResolutionError.bookmarkStale {
    // Need to recreate bookmark
    let newHolder = try await MediaHolder.createSecurityScoped(from: newURL)
}
```

## Timeline

1. **Phase 1**: Add CYBMediaHolder, use for new features
2. **Phase 2**: Migrate existing code to use MediaHolder
3. **Phase 3**: Remove CYBMedia dependency

## FAQ

**Q: Can I use both packages simultaneously?**
A: Yes, they are independent. Use `MediaMigrationService` to convert.

**Q: What about existing saved data using CYBMedia?**
A: Load with CYBMedia, convert via migration context, save new format.

**Q: Is MediaHolder thread-safe?**
A: Yes. `MediaStore` is an actor, descriptor/locator are immutable.

**Q: How do I handle VFR (variable frame rate)?**
A: Check `descriptor.primaryVideoTrack?.isVFR`. Use keyframe index for accurate seeking.
