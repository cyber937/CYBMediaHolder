# Cache System

CYBMediaHolder provides a hierarchical L1/L2 caching system for efficient storage and retrieval of analysis results.

## Goals

- Avoid recomputation of expensive analysis
- Persist results across app sessions
- Keep memory usage predictable
- Provide fast access to frequently used data

## Architecture

```text
┌─────────────────────────────────────────────┐
│              CacheManager                    │
│         (Unified Orchestrator)               │
├─────────────────────────────────────────────┤
│  L1: InMemoryMediaCache                     │
│  - LRU eviction                             │
│  - O(1) access                              │
│  - Process-lifetime only                    │
├─────────────────────────────────────────────┤
│  L2: DiskMediaCache                         │
│  - PropertyListEncoder                      │
│  - ~/Library/Caches/CYBMediaHolder          │
│  - Version-tolerant                         │
└─────────────────────────────────────────────┘
```

## Cache Strategy

| Strategy       | Behavior                                    |
| -------------- | ------------------------------------------- |
| Write-through  | Data written to both L1 and L2 on store     |
| Read-through   | L2 hits promoted to L1 for faster access    |
| LRU eviction   | Both caches use LRU to manage capacity      |

## Basic Usage

```swift
let cache = CacheManager.shared

// Store analysis data (writes to both L1 and L2)
try await cache.store(waveform, for: key)

// Retrieve (checks L1 first, then L2 with promotion)
if let cached = try await cache.retrieve(WaveformData.self, for: key) {
    displayWaveform(cached)
}
```

## Performance Characteristics

| Operation         | L1 Hit   | L2 Hit            |
| ----------------- | -------- | ----------------- |
| Access time       | ~1ms     | ~10-50ms          |
| Subsequent access | ~1ms     | ~1ms (promoted)   |

## Configuration

### Default Configuration

```swift
let config = CacheManager.Configuration.default
// writeToL2: true
// promoteL2Hits: true
// asyncL2Writes: true (non-blocking)
```

### Memory-Only Configuration

```swift
let config = CacheManager.Configuration.memoryOnly
// writeToL2: false
// promoteL2Hits: false
// asyncL2Writes: false
```

### Custom Configuration

```swift
let config = CacheManager.Configuration(
    writeToL2: true,
    promoteL2Hits: true,
    asyncL2Writes: false  // Synchronous for data safety
)

let cache = CacheManager(
    memoryCache: InMemoryMediaCache.shared,
    diskCache: DiskMediaCache.shared,
    configuration: config
)
```

## Cache Operations

### Store

```swift
// Writes to L1 immediately, L2 asynchronously (default)
try await cache.store(data, for: key)
```

### Retrieve

```swift
// Checks L1, then L2 (promotes hit to L1)
if let data = try await cache.retrieve(WaveformData.self, for: key) {
    // Use cached data
}
```

### Remove

```swift
// Remove specific entry from both levels
await cache.remove(for: key)

// Remove all entries for a media ID
await cache.removeAll(for: mediaID)

// Clear all cache entries
await cache.clear()
```

### Check Existence

```swift
if await cache.contains(key) {
    // Entry exists in L1 or L2
}
```

## Cache Warming

Pre-load frequently accessed items into L1:

```swift
let keys = [
    MediaCacheKey.waveform(for: id1),
    MediaCacheKey.waveform(for: id2),
    MediaCacheKey.waveform(for: id3)
]

try await cache.warmUp(WaveformData.self, for: keys)
```

## Statistics

```swift
let stats = await cache.statistics()

print("L1 entries: \(stats.l1.entryCount)")
print("L2 entries: \(stats.l2.entryCount)")
print("Hit rate: \(stats.hitRate * 100)%")
print("L1 hit rate: \(stats.l1HitRate * 100)%")
print("L2 hit rate: \(stats.l2HitRate * 100)%")
print("Total memory: \(stats.totalMemoryBytes) bytes")
```

### CombinedCacheStatistics

```swift
public struct CombinedCacheStatistics: Sendable {
    public let l1: CacheStatistics
    public let l2: CacheStatistics
    public let l1HitCount: Int
    public let l2HitCount: Int
    public let missCount: Int

    public var totalAccesses: Int
    public var hitRate: Double
    public var l1HitRate: Double
    public var l2HitRate: Double
    public var totalEntries: Int
    public var totalMemoryBytes: Int
}
```

## CacheValidity

Each cached entry includes validity information:

```swift
public struct CacheValidity: Codable, Sendable {
    public let version: String
    public let sourceBackend: String
    public let sourceHash: String?
    public let createdAt: Date
    public let expiresAt: Date?  // Default: 30 days

    public var isValid: Bool
    public var isExpired: Bool
}
```

### Validity Checks

- **Time-based:** Entries expire after 30 days by default
- **Hash-based:** Optional source hash for change detection
- **Version-based:** Cache format version compatibility

## Implementations

### InMemoryMediaCache (L1)

Fast in-memory cache with LRU eviction:

```swift
let memoryCache = InMemoryMediaCache.shared

// Direct L1 access
try await memoryCache.store(data, for: key)
let cached = try await memoryCache.retrieve(type, for: key)
```

- LRU eviction policy
- O(1) access time
- Process-lifetime only (volatile)

### DiskMediaCache (L2)

Persistent disk cache:

```swift
let diskCache = DiskMediaCache.shared

// Direct L2 access
try await diskCache.store(data, for: key)
let cached = try await diskCache.retrieve(type, for: key)
```

- PropertyListEncoder for serialization
- Storage: `~/Library/Caches/CYBMediaHolder/`
- Version-tolerant decoding

## Integration with MediaStore

Analysis results are automatically cached via `MediaStore`:

```swift
// Analysis service stores result
let waveform = try await MediaAnalysisService.shared.generateWaveform(for: holder)

// MediaStore provides cached access
if let cached = await holder.getWaveform() {
    // From cache
}
```

## Thread Safety

All cache components are actors:

- `CacheManager` - actor
- `InMemoryMediaCache` - actor
- `DiskMediaCache` - actor

All operations are async and thread-safe.

## Best Practices

1. **Use CacheManager** for unified access (don't access L1/L2 directly)
2. **Warm up cache** for frequently accessed items at app launch
3. **Monitor statistics** to tune cache size
4. **Clear cache** when media is deleted
5. **Use async L2 writes** (default) for better performance
6. **Sync L2 writes** only when data safety is critical
