# Services

This document describes the service layer in CYBMediaHolder.

## MediaProbe Protocol

Protocol-based abstraction for probing media metadata:

```swift
public protocol MediaProbe: Sendable {
    func probe(locator: MediaLocator) async throws -> MediaDescriptor
}
```

## Probe Implementations

### AVFoundationMediaProbe

Default probe using Apple's AVFoundation:

```swift
let probe = AVFoundationMediaProbe()
let descriptor = try await probe.probe(locator: locator)
```

Features:

- Full metadata extraction
- Color space detection
- HDR metadata
- Track enumeration
- Timecode extraction (via `probeExtended()`)

Extended probing with timecode:

```swift
let probe = AVFoundationMediaProbe()
let result = try await probe.probeExtended(locator: locator)

let descriptor = result.descriptor
let timecode = result.timecode  // TimecodeExtractionResult?
```

### ImageMediaProbe

Specialized probe for image files:

```swift
let probe = ImageMediaProbe()
let descriptor = try await probe.probe(locator: locator)
```

Supported formats:

- JPEG, PNG, GIF, TIFF
- HEIC, HEIF
- WebP, BMP, ICO

Auto-detection in `MediaHolder.create()`:

```swift
// Automatically uses ImageMediaProbe for image files
let holder = try await MediaHolder.create(from: imageURL)
print(holder.isImage)  // true
```

### Planned Probes

| Probe              | Status    | Use Case                  |
| ------------------ | --------- | ------------------------- |
| `FFmpegMediaProbe` | Planned   | Extended codec support    |
| `REDMediaProbe`    | Planned   | RED RAW (.r3d)            |
| `BRAWMediaProbe`   | Planned   | Blackmagic RAW (.braw)    |

## MediaProbeRegistry

Central registry for probe management:

```swift
public actor MediaProbeRegistry {
    public static let shared: MediaProbeRegistry

    public func register(_ probe: MediaProbe, for extensions: [String])
    public func probe(for extension: String) -> MediaProbe?
    public func defaultProbe() -> MediaProbe
}
```

### Registering Custom Probes

```swift
let registry = MediaProbeRegistry.shared

// Register for specific extensions
await registry.register(MyCustomProbe(), for: ["custom", "myformat"])

// Probe selection
let probe = await registry.probe(for: "custom")
```

## MediaAnalysisService

Actor-based service for analysis operations. See [ANALYSIS.md](ANALYSIS.md) for details.

```swift
public actor MediaAnalysisService {
    public static let shared: MediaAnalysisService

    // Individual analysis
    public func generateWaveform(for:samplesPerSecond:progress:) async throws -> WaveformData
    public func generatePeak(for:windowSize:progress:) async throws -> PeakData
    public func generateKeyframeIndex(for:progress:) async throws -> KeyframeIndex

    // Parallel analysis
    public func generateAllAnalysis(for:options:progress:) async throws -> AnalysisState

    // Task management
    public func cancelAnalysis(for:)
    public func cancelAll()
    public func isAnalyzing(_:) -> Bool
}
```

Features:

- Task deduplication per MediaID
- Progress reporting
- Cache reuse
- Parallel execution (55% faster)

## CodecRegistry

Central codec knowledge database:

```swift
public enum CodecRegistry {
    public static func displayName(for fourCC: String) -> String
    public static func characteristics(for fourCC: String) -> CodecCharacteristics?
    public static func supportsReversePlayback(_ fourCC: String) -> Bool
    public static func isIntraOnly(_ fourCC: String) -> Bool
}
```

### CodecCharacteristics

```swift
public struct CodecCharacteristics: Sendable {
    public let bitDepth: Int?
    public let chromaSubsampling: ChromaSubsampling?
    public let isIntraOnly: Bool
    public let supportsAlpha: Bool
}
```

### Supported Codecs

Over 50 codecs with metadata:

| Category    | Examples                              |
| ----------- | ------------------------------------- |
| H.264/AVC   | avc1, avc3                            |
| H.265/HEVC  | hvc1, hev1, dvh1 (Dolby Vision)       |
| ProRes      | apch, apcn, apcs, apco, ap4h, ap4x    |
| DNxHD/HR    | AVdh, AVdn                            |
| VP8/VP9     | vp08, vp09                            |
| AV1         | av01                                  |
| Audio       | aac, mp3, alac, flac, opus            |

### Reverse Playback Detection

```swift
if CodecRegistry.supportsReversePlayback("ap4h") {
    // ProRes 4444 supports reverse playback (all-intra)
    enableReversePlayback()
}

if CodecRegistry.supportsReversePlayback("avc1") {
    // H.264 does NOT support efficient reverse (GOP-based)
    // Returns false
}
```

### Intra-Only Detection

```swift
if CodecRegistry.isIntraOnly("apch") {
    // ProRes 422 HQ is all-intra
    // Frame-accurate seeking is efficient
}
```

## CacheManager

Hierarchical caching service. See [CACHE.md](CACHE.md) for details.

```swift
public actor CacheManager {
    public static let shared: CacheManager

    public func store<T: Codable>(_:for:) async throws
    public func retrieve<T: Codable>(_:for:) async throws -> T?
    public func remove(for:) async
    public func clear() async
    public func statistics() async -> CombinedCacheStatistics
}
```

## MediaFileValidator

File validation service. See [VALIDATION.md](VALIDATION.md) for details.

```swift
public struct MediaFileValidator: Sendable {
    public init(config: MediaValidationConfig = .default)

    public func validate(url: URL) throws
    public func validate(path: String) throws
    public func detectSignature(url: URL) throws -> MediaFileSignature
}
```

## Service Integration

Services work together in the typical workflow:

```swift
// 1. Validation (automatic in create)
let holder = try await MediaHolder.create(from: url)
// Uses MediaFileValidator internally

// 2. Probing (automatic in create)
// Uses AVFoundationMediaProbe or ImageMediaProbe

// 3. Analysis
let result = try await MediaAnalysisService.shared.generateAllAnalysis(for: holder)
// Results automatically cached via MediaStore

// 4. Cache access
if let waveform = await holder.getWaveform() {
    // Retrieved from cache
}
```

## Thread Safety

All services are designed for concurrent access:

| Service                 | Type    | Thread-Safe   |
| ----------------------- | ------- | ------------- |
| `MediaAnalysisService`  | actor   | Yes           |
| `MediaProbeRegistry`    | actor   | Yes           |
| `CacheManager`          | actor   | Yes           |
| `MediaFileValidator`    | struct  | Yes (Sendable)|
| `CodecRegistry`         | enum    | Yes (static)  |

## Extensibility

### Custom Probes

```swift
struct MyCustomProbe: MediaProbe {
    func probe(locator: MediaLocator) async throws -> MediaDescriptor {
        // Custom probing logic
    }
}

// Register
await MediaProbeRegistry.shared.register(MyCustomProbe(), for: ["myext"])
```

### Custom Analyzers

Implement `MediaAnalyzer` protocol:

```swift
public protocol MediaAnalyzer: Sendable {
    associatedtype Result: Sendable

    func analyze(
        holder: MediaHolder,
        progress: AnalysisProgressHandler?
    ) async throws -> Result
}
```
