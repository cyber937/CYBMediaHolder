# Timecode Support

CYBMediaHolder provides comprehensive timecode extraction and availability detection for professional video workflows.

## Overview

Timecode is treated as an immutable fact about the media, stored in `TimecodeExtractionResult` and accessible via `MediaHolder`.

## Timecode Availability

Before displaying timecode, check its availability to determine confidence level:

```swift
let availability = mediaHolder.timecodeAvailability()

switch availability {
case .available:
    // High confidence - from tmcd track or metadata
    showTimecode(mediaHolder.getTimecodeStart()!)

case .inferable:
    // Low confidence - estimated (typically 00:00:00:00)
    showTimecode(mediaHolder.getTimecodeStart()!, isEstimated: true)

case .unavailable:
    // No timecode data
    showPlaceholder("--:--:--:--")
}
```

### Availability States

| State         | Source                    | Confidence | Use Case                    |
| ------------- | ------------------------- | ---------- | --------------------------- |
| `.available`  | tmcd track or metadata    | High       | Display with confidence     |
| `.inferable`  | Estimated from duration   | Low        | Display with indicator      |
| `.unavailable`| Not determinable          | None       | Show placeholder            |

## Accessing Timecode Data

```swift
// Start timecode (e.g., "01:00:00:00")
let start = mediaHolder.getTimecodeStart()

// Frame rate (e.g., 24.0, 29.97)
let rate = mediaHolder.getTimecodeRate()

// Drop-frame flag
let isDropFrame = mediaHolder.getTimecodeDropFrame()

// Source kind ("tmcd", "metadata", "inferred")
let source = mediaHolder.getTimecodeSourceKind()
```

## Capability Flags

Timecode capabilities are included in the capability set:

```swift
let caps = await holder.capabilities

if caps.contains(.timecodeAvailable) {
    // Explicit timecode from embedded source
    enableTimecodeDisplay()
}

if caps.contains(.timecodeInferable) {
    // Estimated timecode available
    enableTimecodeDisplay(showEstimatedIndicator: true)
}
```

## TimecodeExtractionResult

The extraction result contains all timecode information:

```swift
public struct TimecodeExtractionResult: Codable, Sendable {
    /// Start timecode string (e.g., "01:00:00:00")
    public let start: String

    /// Timecode rate (frame rate)
    public let rate: Double

    /// Whether drop-frame format is used
    public let dropFrame: Bool

    /// Source kind: "tmcd", "metadata", or "inferred"
    public let sourceKind: String
}
```

## Source Kinds

### tmcd Track

Timecode extracted from a dedicated timecode track (QuickTime tmcd atom).

- **Confidence:** High
- **Common in:** Professional cameras, NLE exports

### Metadata

Timecode extracted from container metadata.

- **Confidence:** High
- **Common in:** MXF, some MP4 files

### Inferred

Timecode estimated when no explicit source exists.

- **Confidence:** Low
- **Default:** 00:00:00:00 at media frame rate
- **Common in:** Consumer cameras, screen recordings

## CoreNormalized Integration

Timecode is included in the normalized metadata layer:

```swift
let store = holder.makeCoreNormalizedStoreWithTimecode()

if let tcStart = store.stringValue(.timecodeStart) {
    print("Start: \(tcStart)")
}

if let tcRate = store.doubleValue(.timecodeRate) {
    print("Rate: \(tcRate) fps")
}

if let dropFrame = store.boolValue(.timecodeDropFrame) {
    print("Drop-frame: \(dropFrame)")
}
```

## Player Integration Example

```swift
class VideoPlayer {
    let holder: MediaHolder

    func setupTimecodeDisplay() {
        switch holder.timecodeAvailability() {
        case .available:
            timecodeLabel.textColor = .primary
            timecodeLabel.text = formatTimecode(
                holder.getTimecodeStart()!,
                rate: holder.getTimecodeRate()!,
                dropFrame: holder.getTimecodeDropFrame()
            )

        case .inferable:
            timecodeLabel.textColor = .secondary
            timecodeLabel.text = formatTimecode(
                holder.getTimecodeStart()!,
                rate: holder.getTimecodeRate()!,
                dropFrame: holder.getTimecodeDropFrame()
            ) + " (est.)"

        case .unavailable:
            timecodeLabel.isHidden = true
        }
    }

    func formatTimecode(_ tc: String, rate: Double, dropFrame: Bool) -> String {
        // Use semicolon separator for drop-frame
        dropFrame ? tc.replacingOccurrences(of: ":", with: ";") : tc
    }
}
```

## Drop-Frame Timecode

Drop-frame timecode is used with 29.97 fps (NTSC) to maintain synchronization with real time.

```swift
if holder.getTimecodeDropFrame() {
    // Display with semicolons: 01;00;00;00
    let formatted = timecode.replacingOccurrences(of: ":", with: ";")
}
```

## Best Practices

1. **Always check availability** before displaying timecode
2. **Indicate estimated timecode** to users (dim color, "(est.)" suffix)
3. **Use drop-frame separator** (`;`) for 29.97 fps content
4. **Cache the extraction result** - it's immutable and won't change
