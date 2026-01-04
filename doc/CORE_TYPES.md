# Core Types

This document describes the fundamental types in CYBMediaHolder.

## MediaID

Stable identity independent of file path.

```swift
public struct MediaID: Hashable, Codable, Sendable, Identifiable {
    public let uuid: UUID
    public let contentHash: String?
    public let bookmarkHash: String?
}
```

### Fields

| Field          | Description                           |
| -------------- | ------------------------------------- |
| `uuid`         | Unique identifier (auto-generated)    |
| `contentHash`  | Content-based hash (future MAM)       |
| `bookmarkHash` | Security-scoped bookmark hash (macOS) |

### Usage

```swift
// Auto-generated ID
let id = MediaID()

// With bookmark hash (sandbox)
let id = MediaID(bookmarkHash: "abc123...")
```

## MediaLocator

Abstracts physical location of media:

```swift
public enum MediaLocator: Codable, Sendable {
    case filePath(String)
    case securityScopedBookmark(Data)
    case url(URL)
    case http(URL, headers: [String: String]?)
    case s3(bucket: String, key: String, region: String?)
}
```

### Location Types

| Case                       | Description                    | Status   |
| -------------------------- | ------------------------------ | -------- |
| `filePath`                 | Local file path                | ✅       |
| `securityScopedBookmark`   | macOS sandbox bookmark         | ✅       |
| `url`                      | Generic URL                    | ✅       |
| `http`                     | HTTP with optional headers     | Planned  |
| `s3`                       | AWS S3 object                  | Planned  |

### Resolution

```swift
let resolved = try await locator.resolve()
defer { resolved.stopAccessing() }

let asset = AVAsset(url: resolved.url)
```

### Security-Scoped Bookmarks

```swift
// Create from security-scoped URL
let locator = try MediaLocator.fromSecurityScopedURL(url)

// Create bookmark directly
let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])
let locator = MediaLocator.securityScopedBookmark(bookmarkData)
```

## MediaDescriptor

Immutable metadata snapshot:

```swift
public struct MediaDescriptor: Codable, Sendable {
    public let containerFormat: String?
    public let durationSeconds: Double
    public let fileName: String?
    public let fileSize: Int64?
    public let creationDate: Date?

    public let videoTracks: [VideoTrackDescriptor]
    public let audioTracks: [AudioTrackDescriptor]

    public let probeBackend: String
    public let keyframeHint: KeyframeHint
    public let mediaType: MediaType
}
```

### Convenience Properties

```swift
holder.descriptor.hasVideo          // Has video tracks
holder.descriptor.hasAudio          // Has audio tracks
holder.descriptor.isHDR             // HDR content detected
holder.descriptor.frameRate         // Primary video frame rate
holder.descriptor.videoSize         // Primary video dimensions
holder.descriptor.primaryVideoTrack // First video track
holder.descriptor.primaryAudioTrack // First audio track
```

### MediaType

```swift
public enum MediaType: String, Codable, Sendable {
    case video
    case audio
    case image
    case unknown
}
```

### KeyframeHint

```swift
public enum KeyframeHint: String, Codable, Sendable {
    case allKeyframes    // All-intra codec (ProRes, DNxHD)
    case hasKeyframes    // GOP-based codec (H.264, H.265)
    case unknown
}
```

## VideoTrackDescriptor

Detailed video track information:

```swift
public struct VideoTrackDescriptor: Codable, Sendable {
    public let trackID: Int
    public let codec: CodecInfo
    public let width: Int
    public let height: Int
    public let nominalFrameRate: Float
    public let colorInfo: ColorInfo
    public let timeRange: CMTimeRange?
    public let estimatedFrameCount: Int?

    // Display aspect ratio
    public let displayWidth: Int?
    public let displayHeight: Int?
    public let isAnamorphic: Bool

    // Variable frame rate
    public let isVFR: Bool
    public let minFrameRate: Float?
    public let maxFrameRate: Float?
}
```

### Anamorphic Detection

```swift
if track.isAnamorphic {
    // Use display dimensions for rendering
    let displaySize = CGSize(
        width: track.displayWidth ?? track.width,
        height: track.displayHeight ?? track.height
    )
}
```

### VFR Detection

```swift
if track.isVFR {
    print("Variable frame rate: \(track.minFrameRate!)-\(track.maxFrameRate!) fps")
}
```

## AudioTrackDescriptor

Detailed audio track information:

```swift
public struct AudioTrackDescriptor: Codable, Sendable {
    public let trackID: Int
    public let codec: CodecInfo
    public let sampleRate: Double
    public let channelCount: Int
    public let channelLayout: String?
    public let bitRate: Int?
    public let languageCode: String?
    public let timeRange: CMTimeRange?
}
```

### Channel Layout

Common layouts: `"stereo"`, `"5.1"`, `"7.1"`, `"mono"`

```swift
if track.channelLayout == "5.1" {
    enableSurroundSound()
}
```

## CodecInfo

Codec identification:

```swift
public struct CodecInfo: Codable, Sendable {
    public let fourCC: String
    public let displayName: String
}
```

Common video codecs:

| FourCC   | Display Name    |
| -------- | --------------- |
| `avc1`   | H.264           |
| `hvc1`   | H.265/HEVC      |
| `ap4h`   | ProRes 4444     |
| `apch`   | ProRes 422 HQ   |

## Capability

Feature flags (OptionSet):

```swift
public struct Capability: OptionSet, Codable, Sendable {
    // Playback
    static let videoPlayback
    static let audioPlayback
    static let randomFrameAccess
    static let frameAccurateSeeking
    static let reversePlayback
    static let variableSpeed

    // Analysis Available
    static let waveformAvailable
    static let peakAvailable
    static let keyframeIndexAvailable
    static let thumbnailIndexAvailable

    // Analysis Generatable
    static let waveformGeneratable
    static let peakGeneratable
    static let keyframeIndexGeneratable
    static let thumbnailGeneratable

    // Color & HDR
    static let colorProfileInspection
    static let hdrMetadata
    static let hdrTonemapping

    // Backend
    static let avFoundationBacked
    static let ffmpegBacked
    static let rawBacked

    // Timecode
    static let timecodeAvailable
    static let timecodeInferable

    // Convenience sets
    static let standardPlayback
    static let fullPlayback
    static let allAnalysisGeneratable
    static let allAnalysisAvailable
}
```

### Capability Usage

```swift
let caps = await holder.capabilities

if caps.contains(.waveformGeneratable) {
    showWaveformButton()
}

if caps.contains(.reversePlayback) {
    enableReversePlayback()
}
```

## MediaStore

Mutable, actor-isolated state:

```swift
public actor MediaStore {
    public var analysisState: AnalysisState
    public var userAnnotations: UserAnnotations
    public var cacheValidity: CacheValidity?

    // Setters
    public func setWaveform(_ data: WaveformData, validity: CacheValidity)
    public func setPeak(_ data: PeakData, validity: CacheValidity)
    public func setKeyframeIndex(_ index: KeyframeIndex, validity: CacheValidity)
    public func setUserAnnotations(_ annotations: UserAnnotations)

    // Task tracking
    public func markTaskPending(_ type: AnalysisType)
    public func markTaskComplete(_ type: AnalysisType)
}
```

## UserAnnotations

User-defined metadata:

```swift
public struct UserAnnotations: Codable, Sendable {
    public var tags: Set<String>
    public var notes: String?
    public var customMarkers: [Double: String]  // time -> label
    public var inPoint: Double?
    public var outPoint: Double?
    public var rating: Int?  // 1-5

    public init()
}
```

### Annotations Example

```swift
var annotations = UserAnnotations()
annotations.tags = ["interview", "b-roll"]
annotations.notes = "Good take, use for intro"
annotations.inPoint = 5.0
annotations.outPoint = 120.0
annotations.rating = 4
annotations.customMarkers = [
    10.5: "Highlight",
    45.0: "Cut here"
]

await holder.store.setUserAnnotations(annotations)
```

## AnalysisState

Aggregate state for analysis data:

```swift
public struct AnalysisState: Sendable {
    public let waveform: WaveformData?
    public let peak: PeakData?
    public let keyframeIndex: KeyframeIndex?
    public let thumbnailIndex: ThumbnailIndex?

    public var isComplete: Bool
    public func hasAnalysis(_ type: AnalysisType) -> Bool
}
```

## AnalysisType

```swift
public enum AnalysisType: String, CaseIterable, Sendable {
    case waveform
    case peak
    case keyframeIndex
    case thumbnailIndex
}
```
