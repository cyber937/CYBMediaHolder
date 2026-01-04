# Core Normalized Metadata Layer

## Motivation

Different backends report different values.
CoreNormalized provides a vendor-independent, typed, provenance-aware layer.

## CoreKey

Stable semantic keys such as:

- videoWidth
- videoCodec
- audioSampleRateHz
- colorHDR

## CoreValue

Type-safe value container:

- int / int64
- double
- bool
- string

## Provenance

Each value tracks:

- source (e.g. avfoundation, ffprobe)
- confidence (optional)

## Resolution Strategy

- First candidate becomes resolved
- Can be re-resolved by confidence

## Usage

```swift
let store = holder.makeCoreNormalizedStore()

if store.boolValue(.colorHDR) == true {
    showHDR()
}
```

Guarantees
• No Any
• Forward-compatible decoding
• All candidates preserved
