# API Guide — CYBMediaHolder

## Creating a MediaHolder

```swift
let holder = try await MediaHolder.create(from: fileURL)
```

## Sandbox-safe creation

```swift
llet holder = try await MediaHolder.createSecurityScoped(from: fileURL)
```

## Accessing Metadata

```swift
holder.duration
holder.descriptor.frameRate
holder.descriptor.isHDR
```

## Capability-based UI

```swift
let caps = await holder.capabilities

if caps.contains(.waveformGeneratable) {
    showWaveformButton()
}
```

## Analysis Services

```swift
let waveform = try await MediaAnalysisService.shared.generateWaveform(
    for: holder,
    samplesPerSecond: 100
)
```

### Cached access

```swift
if let cached = await holder.getWaveform() {
    displayWaveform(cached)
}
```

## Player Integration

```swift
let resolved = try await holder.locator.resolve()
defer { resolved.stopAccessing() }

let asset = AVAsset(url: resolved.url)
```
