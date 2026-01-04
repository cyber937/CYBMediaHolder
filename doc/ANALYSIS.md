# Analysis System

CYBMediaHolder provides a comprehensive media analysis system for generating waveforms, peak data, and keyframe indices.

## Overview

The analysis system is built around `MediaAnalysisService`, an actor that coordinates long-running analysis tasks with:

- Task deduplication (prevents redundant analysis)
- Progress reporting
- Parallel execution
- Automatic cache integration

## Analysis Types

### Waveform Analysis

Generates audio waveform visualization data.

```swift
let waveform = try await MediaAnalysisService.shared.generateWaveform(
    for: holder,
    samplesPerSecond: 100,
    progress: { progress in
        print("Waveform: \(Int(progress * 100))%")
    }
)
```

**Performance optimizations:**

- Float32 direct output from AVAssetReader (eliminates Int16→Float conversion)
- Accelerate framework SIMD for min/max operations
- `vDSP_vgathr` for efficient stereo channel extraction
- 32KB buffer for optimal SIMD batch processing

**Output:** `WaveformData` containing min/max sample pairs per time window.

### Peak Analysis

Generates peak amplitude data for level metering and beat detection.

```swift
let peak = try await MediaAnalysisService.shared.generatePeak(
    for: holder,
    windowSize: 4800,  // 0.1s at 48kHz
    progress: nil
)
```

**Performance optimizations:**

- `vDSP_maxmgv` for SIMD peak detection
- Batch processing to minimize per-sample overhead
- Pre-allocated buffers

**Output:** `PeakData` with maximum amplitude per window (normalized 0.0-1.0).

### Keyframe Indexing

Builds an index of keyframe positions for fast seeking.

```swift
let keyframes = try await MediaAnalysisService.shared.generateKeyframeIndex(
    for: holder,
    progress: nil
)
```

**Hybrid strategy:**

| Duration   | Mode     | Behavior                              |
| ---------- | -------- | ------------------------------------- |
| < 5 min    | Complete | Scans all frames for accurate index   |
| >= 5 min   | Sampled  | Seeks at 2-second intervals           |

The sampled approach provides keyframe timestamps at regular intervals, sufficient for scrubbing and seeking.

**Output:** `KeyframeIndex` with timestamps and frame numbers.

## Parallel Analysis

For optimal performance, use `generateAllAnalysis()` to run all applicable analyses in parallel.

```swift
let result = try await MediaAnalysisService.shared.generateAllAnalysis(
    for: holder,
    options: .all,
    progress: { combined in
        updateProgressBar(combined)
    }
)

// Access results
if let waveform = result.waveform { ... }
if let peak = result.peak { ... }
if let keyframes = result.keyframeIndex { ... }
```

**Performance comparison:**

| Execution  | Time   | Improvement |
| ---------- | ------ | ----------- |
| Sequential | ~23s   | baseline    |
| Parallel   | ~10s   | 55% faster  |

## Analysis Options

Control which analyses to perform:

```swift
// Audio only
let result = try await service.generateAllAnalysis(
    for: holder,
    options: .audio  // .waveform + .peak
)

// Video only
let result = try await service.generateAllAnalysis(
    for: holder,
    options: .video  // .keyframeIndex + .thumbnailIndex
)

// Selective
let result = try await service.generateAllAnalysis(
    for: holder,
    options: [.waveform, .keyframeIndex]
)
```

Available options:

- `.waveform` - Audio waveform data
- `.peak` - Audio peak levels
- `.keyframeIndex` - Video keyframe positions
- `.thumbnailIndex` - Video preview thumbnails
- `.audio` - All audio analyses
- `.video` - All video analyses
- `.all` - All analyses (default)

## Task Deduplication

The service automatically prevents duplicate analysis runs:

```swift
// These run the same analysis only once
async let a = service.generateWaveform(for: holder)
async let b = service.generateWaveform(for: holder)

// Both await the same underlying task
let (result1, result2) = try await (a, b)
```

## Cancellation

Cancel analysis for a specific holder or all active analyses:

```swift
// Cancel specific holder
await service.cancelAnalysis(for: holder)

// Cancel all
await service.cancelAll()

// Check if analyzing
let isActive = await service.isAnalyzing(holder)
```

## Cache Integration

Analysis results are automatically stored in `MediaStore`:

```swift
// Results are cached after generation
let waveform = try await service.generateWaveform(for: holder)

// Retrieve from cache (fast)
if let cached = await holder.getWaveform() {
    displayWaveform(cached)
}
```

## Error Handling

```swift
do {
    let waveform = try await service.generateWaveform(for: holder)
} catch MediaAnalysisError.noAudioTrack {
    print("Media has no audio")
} catch MediaAnalysisError.cancelled {
    print("Analysis was cancelled")
} catch MediaAnalysisError.audioReadFailed(let error) {
    print("Failed to read audio: \(error)")
}
```

Error types:

- `noAudioTrack` - No audio track for audio analysis
- `noVideoTrack` - No video track for video analysis
- `audioReadFailed(Error)` - Audio reading failed
- `videoReadFailed(Error)` - Video reading failed
- `cancelled` - Analysis was cancelled
- `locatorResolutionFailed(Error)` - Could not resolve media location
- `analysisFailed(Error)` - Generic analysis failure

## Data Types

### WaveformData

```swift
public struct WaveformData: Codable, Sendable {
    public let samplesPerSecond: Int
    public let minSamples: [Float]
    public let maxSamples: [Float]
    public let channelCount: Int
}
```

### PeakData

```swift
public struct PeakData: Codable, Sendable {
    public let windowSize: Int
    public let peaks: [Float]  // Normalized 0.0-1.0
}
```

### KeyframeIndex

```swift
public struct KeyframeIndex: Codable, Sendable {
    public let times: [Double]       // Seconds
    public let frameNumbers: [Int]
}
```

### AnalysisState

Aggregate state for all analysis data:

```swift
public struct AnalysisState: Sendable {
    public let waveform: WaveformData?
    public let peak: PeakData?
    public let keyframeIndex: KeyframeIndex?
    public let thumbnailIndex: ThumbnailIndex?
}
```
