# Color Management

CYBMediaHolder provides comprehensive color space and HDR metadata handling for accurate video rendering.

## Overview

Color information is encapsulated in `ColorInfo`, which contains:

- Color primaries (gamut)
- Transfer function (gamma/EOTF)
- Matrix coefficients (YCbCr conversion)
- Bit depth and chroma subsampling

## Accessing Color Information

```swift
let holder = try await MediaHolder.create(from: videoURL)

if let videoTrack = holder.descriptor.primaryVideoTrack {
    let colorInfo = videoTrack.colorInfo

    print("Primaries: \(colorInfo.primaries ?? .unknown)")
    print("Transfer: \(colorInfo.transferFunction ?? .unknown)")
    print("HDR: \(colorInfo.isHDR)")
    print("Bit depth: \(colorInfo.bitDepth ?? 8)")
}
```

## Color Primaries

Defines the RGB primary chromaticities:

| Primaries     | Description           | Use Case                |
| ------------- | --------------------- | ----------------------- |
| `.bt709`      | ITU-R BT.709          | Standard HD, sRGB       |
| `.bt2020`     | ITU-R BT.2020         | Ultra HD, HDR           |
| `.p3`         | DCI-P3                | Digital Cinema          |
| `.bt601NTSC`  | ITU-R BT.601 NTSC     | SD NTSC                 |
| `.bt601PAL`   | ITU-R BT.601 PAL      | SD PAL                  |
| `.unknown`    | Unspecified           | Fallback                |

```swift
switch colorInfo.primaries {
case .bt709:
    // Standard HD color space
    useRec709Pipeline()
case .bt2020:
    // Wide color gamut
    useWideGamutPipeline()
case .p3:
    // Digital cinema
    useP3Pipeline()
default:
    // Assume Rec.709
    useRec709Pipeline()
}
```

## Transfer Functions

Defines the electro-optical transfer function (EOTF/gamma):

| Transfer  | Description           | HDR?  | Use Case              |
| --------- | --------------------- | ----- | --------------------- |
| `.bt709`  | BT.709 (gamma ~2.4)   | No    | Standard HD           |
| `.sRGB`   | sRGB (gamma ~2.2)     | No    | Web, displays         |
| `.hlg`    | Hybrid Log-Gamma      | Yes   | HDR broadcast         |
| `.pq`     | PQ / ST.2084          | Yes   | HDR cinema, streaming |
| `.linear` | Linear (gamma 1.0)    | No    | Compositing           |
| `.unknown`| Unspecified           | No    | Fallback              |

```swift
if colorInfo.transferFunction?.isHDR == true {
    enableHDRRendering()
}
```

## Matrix Coefficients

Defines the RGB to YCbCr conversion matrix:

| Matrix        | Description               |
| ------------- | ------------------------- |
| `.bt709`      | ITU-R BT.709              |
| `.bt2020NCL`  | BT.2020 non-constant luma |
| `.bt2020CL`   | BT.2020 constant luma     |
| `.bt601`      | ITU-R BT.601              |
| `.identity`   | RGB (no conversion)       |
| `.unknown`    | Unspecified               |

## HDR Detection

Quick HDR detection:

```swift
// Via ColorInfo
if colorInfo.isHDR {
    setupHDRDisplay()
}

// Via descriptor convenience
if holder.descriptor.isHDR {
    setupHDRDisplay()
}

// Via capability
if holder.baseCapabilities.contains(.hdrMetadata) {
    setupHDRDisplay()
}
```

HDR is detected when:

- Transfer function is HLG or PQ
- Color primaries is BT.2020

## Bit Depth

Common bit depths:

| Depth | Description           | Use Case              |
| ----- | --------------------- | --------------------- |
| 8     | Standard              | SDR, consumer video   |
| 10    | Extended              | HDR, professional     |
| 12    | High precision        | Cinema, mastering     |

```swift
if let bitDepth = colorInfo.bitDepth, bitDepth > 8 {
    useHighPrecisionPipeline()
}
```

## Chroma Subsampling

| Subsampling | Description           | Quality       |
| ----------- | --------------------- | ------------- |
| `.cs444`    | 4:4:4 (no subsampling)| Highest       |
| `.cs422`    | 4:2:2                 | Broadcast     |
| `.cs420`    | 4:2:0                 | Consumer      |
| `.cs411`    | 4:1:1                 | Legacy DV     |

```swift
if colorInfo.chromaSubsampling == .cs444 {
    // Full chroma resolution
}
```

## Video Range

```swift
if colorInfo.isFullRange == true {
    // 0-255 (full range)
} else {
    // 16-235 (video/limited range)
}
```

## Default SDR Configuration

```swift
let sdrConfig = ColorInfo.sdrRec709
// primaries: .bt709
// transferFunction: .bt709
// matrix: .bt709
// isFullRange: false
// bitDepth: 8
// chromaSubsampling: .cs420
```

## Integration with CoreNormalized

Color information is available in the normalized metadata layer:

```swift
let store = holder.makeCoreNormalizedStore()

if store.boolValue(.colorHDR) == true {
    print("HDR content")
}
```

## Metal/CoreImage Integration

Example color space setup for Metal rendering:

```swift
func metalColorSpace(for colorInfo: ColorInfo) -> CGColorSpace? {
    switch (colorInfo.primaries, colorInfo.transferFunction) {
    case (.bt2020, .pq):
        return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
    case (.bt2020, .hlg):
        return CGColorSpace(name: CGColorSpace.itur_2100_HLG)
    case (.p3, _):
        return CGColorSpace(name: CGColorSpace.displayP3)
    default:
        return CGColorSpace(name: CGColorSpace.itur_709)
    }
}
```

## Best Practices

1. **Always check for HDR** before rendering to avoid incorrect display
2. **Use capability flags** for UI decisions (show HDR badge, etc.)
3. **Fall back to BT.709** when color info is unknown
4. **Consider bit depth** when choosing rendering precision
5. **Handle video range** to avoid crushed blacks or clipped whites
