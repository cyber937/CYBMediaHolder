# Roadmap

This document outlines the development status and future plans for CYBMediaHolder.

## Implemented Features

### Core

- [x] MediaID - Stable identity with UUID and bookmark hash
- [x] MediaLocator - File path, security-scoped bookmark, URL
- [x] MediaDescriptor - Immutable metadata snapshot
- [x] MediaStore - Actor-isolated mutable state
- [x] Capability - Feature flag system

### Probing

- [x] AVFoundationMediaProbe - Full video/audio probing
- [x] ImageMediaProbe - Image file support
- [x] Timecode extraction - tmcd track and metadata
- [x] Extended probing with TimecodeExtractionResult

### Analysis

- [x] WaveformAnalyzer - SIMD-optimized audio waveform
- [x] PeakAnalyzer - Audio peak detection
- [x] KeyframeIndexer - Hybrid complete/sampled strategy
- [x] Parallel analysis - 55% performance improvement
- [x] Task deduplication - Prevents redundant analysis
- [x] Progress reporting

### Cache

- [x] L1 InMemoryMediaCache - LRU, O(1) access
- [x] L2 DiskMediaCache - Persistent storage
- [x] CacheManager - Hierarchical orchestration
- [x] Write-through strategy
- [x] L2 hit promotion
- [x] CacheValidity - Time and hash based

### Color

- [x] ColorInfo - Complete color metadata
- [x] ColorPrimaries - BT.709, BT.2020, P3, BT.601
- [x] TransferFunction - BT.709, sRGB, HLG, PQ
- [x] MatrixCoefficients - BT.709, BT.2020, BT.601
- [x] HDR detection

### Validation

- [x] MediaFileValidator - Pre-load validation
- [x] Magic number detection - 20+ formats
- [x] Symlink protection
- [x] Path safety checks
- [x] File size limits

### Other

- [x] CodecRegistry - 50+ codecs with characteristics
- [x] UserAnnotations - Tags, notes, markers, ratings
- [x] CoreNormalized - Vendor-independent metadata layer
- [x] Swift Concurrency - Actor isolation, Sendable

## Planned Features

### Planned Probing

- [ ] FFmpegMediaProbe - Extended codec support
- [ ] REDMediaProbe - RED RAW (.r3d) support
- [ ] BRAWMediaProbe - Blackmagic RAW support
- [ ] ProResRAWMediaProbe - ProRes RAW support

### Planned Locators

- [ ] HTTP Range support - Remote media with headers
- [ ] S3 locator - AWS S3 object storage
- [ ] Cloud storage abstraction

### Planned Analysis

- [ ] ThumbnailIndex - Video preview thumbnails
- [ ] GPU-accelerated analysis - Metal compute
- [ ] Loudness analysis - EBU R128, ITU-R BS.1770

### Planned Color

- [ ] HDR mastering metadata - Max/min luminance
- [ ] Dolby Vision profile detection
- [ ] ICC profile support

### Planned Serialization

- [ ] CBOR persistence - Compact binary format
- [ ] MessagePack support
- [ ] Protocol Buffers option

### Integration

- [ ] PluginRegistry - Dynamic probe/analyzer loading
- [ ] CloudKit sync - Cross-device metadata
- [ ] Spotlight integration - macOS search

## Non-Goals

The following are explicitly out of scope:

- Playback implementation (AVPlayer, custom players)
- Video editing / timeline
- Transcoding / export
- UI frameworks or components
- Real-time streaming protocols

## Version History

### 0.1.0 (Current)

- Initial release
- Core types and architecture
- AVFoundation and Image probing
- Analysis system (waveform, peak, keyframe)
- Hierarchical caching
- File validation
- Color management
- Timecode support

## Contributing

Contributions are welcome. Priority areas:

1. Additional probe implementations (FFmpeg, RAW formats)
2. Performance optimizations
3. Test coverage
4. Documentation improvements

See the project repository for contribution guidelines.
