//
//  CYBMediaHolderTests.swift
//  CYBMediaHolderTests
//
//  Unit tests for CYBMediaHolder package.
//

import XCTest
import CoreMedia
@testable import CYBMediaHolder

final class CYBMediaHolderTests: XCTestCase {

    // MARK: - MediaID Tests

    func testMediaIDCreation() {
        let id = MediaID()
        XCTAssertNotNil(id.uuid)
        XCTAssertNil(id.contentHash)
        XCTAssertNil(id.bookmarkHash)
    }

    func testMediaIDWithHashes() {
        let id = MediaID(contentHash: "abc123", bookmarkHash: "def456")
        XCTAssertEqual(id.contentHash, "abc123")
        XCTAssertEqual(id.bookmarkHash, "def456")
    }

    func testMediaIDEquality() {
        let uuid = UUID()
        let id1 = MediaID(uuid: uuid)
        let id2 = MediaID(uuid: uuid)
        XCTAssertEqual(id1, id2)
    }

    func testMediaIDCodable() throws {
        let original = MediaID(contentHash: "test")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MediaID.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - MediaLocator Tests

    func testFilePathLocator() {
        let locator = MediaLocator.filePath("/test/path.mov")
        XCTAssertTrue(locator.isLocal)
        XCTAssertFalse(locator.requiresNetwork)
        XCTAssertEqual(locator.filePath, "/test/path.mov")
    }

    func testURLLocator() {
        let url = URL(fileURLWithPath: "/test/path.mov")
        let locator = MediaLocator.url(url)
        XCTAssertTrue(locator.isLocal)
        XCTAssertEqual(locator.filePath, "/test/path.mov")
    }

    func testHTTPLocator() {
        let url = URL(string: "https://example.com/video.mp4")!
        let locator = MediaLocator.http(url: url, supportsRangeRequests: true)
        XCTAssertFalse(locator.isLocal)
        XCTAssertTrue(locator.requiresNetwork)
    }

    func testLocatorFromFileURL() {
        let url = URL(fileURLWithPath: "/test/video.mov")
        let locator = MediaLocator.fromFileURL(url)
        XCTAssertNotNil(locator)
        XCTAssertEqual(locator?.filePath, "/test/video.mov")
    }

    func testLocatorCodable() throws {
        let original = MediaLocator.filePath("/test/path.mov")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MediaLocator.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - ColorInfo Tests

    func testColorInfoSDR() {
        let colorInfo = ColorInfo.sdrRec709
        XCTAssertEqual(colorInfo.primaries, .bt709)
        XCTAssertEqual(colorInfo.transferFunction, .bt709)
        XCTAssertFalse(colorInfo.isHDR)
        XCTAssertTrue(colorInfo.isSDRRec709)
    }

    func testColorInfoHDR() {
        let colorInfo = ColorInfo(
            primaries: .bt2020,
            transferFunction: .pq,
            matrix: .bt2020NCL,
            bitDepth: 10
        )
        XCTAssertTrue(colorInfo.isHDR)
        XCTAssertFalse(colorInfo.isSDRRec709)
    }

    // MARK: - Capability Tests

    func testCapabilityBasics() {
        var caps = Capability()
        XCTAssertTrue(caps.isEmpty)

        caps.insert(.videoPlayback)
        XCTAssertTrue(caps.contains(.videoPlayback))

        caps.insert(.audioPlayback)
        XCTAssertTrue(caps.contains([.videoPlayback, .audioPlayback]))
    }

    func testCapabilitySets() {
        let standard = Capability.standardPlayback
        XCTAssertTrue(standard.contains(.videoPlayback))
        XCTAssertTrue(standard.contains(.audioPlayback))
        XCTAssertTrue(standard.contains(.randomFrameAccess))
    }

    func testCapabilityCodable() throws {
        let original = Capability.standardPlayback
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Capability.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - TrackDescriptor Tests

    func testCodecInfo() {
        let codec = CodecInfo(fourCC: "avc1", displayName: "H.264/AVC")
        XCTAssertEqual(codec.fourCC, "avc1")
        XCTAssertEqual(codec.displayName, "H.264/AVC")
    }

    func testFourCharCodeConversion() {
        let fourCC: FourCharCode = 0x61766331 // 'avc1'
        let string = fourCC.asString
        XCTAssertEqual(string, "avc1")
    }

    // MARK: - MediaDescriptor Tests

    func testMediaDescriptorBasics() {
        let container = ContainerInfo(
            format: "QuickTime",
            fileExtension: "mov"
        )
        let descriptor = MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "Test"
        )

        XCTAssertEqual(descriptor.mediaType, MediaType.video)
        XCTAssertEqual(descriptor.durationSeconds, 60, accuracy: 0.01)
        XCTAssertFalse(descriptor.hasVideo)
        XCTAssertFalse(descriptor.hasAudio)
    }

    // MARK: - MediaStore Tests

    func testMediaStoreAnalysisState() async {
        let store = MediaStore()

        // Initially empty
        let state = await store.analysisState
        XCTAssertNil(state.waveform)
        XCTAssertNil(state.peak)
    }

    func testMediaStoreWaveformStorage() async {
        let store = MediaStore()

        let waveform = WaveformData(
            samplesPerSecond: 100,
            minSamples: [0.1, 0.2],
            maxSamples: [0.5, 0.6],
            channelCount: 2
        )
        let validity = CacheValidity(
            version: "1.0",
            sourceBackend: "Test",
            sourceHash: nil
        )

        await store.setWaveform(waveform, validity: validity)

        let hasWaveform = await store.hasWaveform
        XCTAssertTrue(hasWaveform)

        let retrieved = await store.analysisState.waveform
        XCTAssertEqual(retrieved?.samplesPerSecond, 100)
    }

    func testMediaStoreTasks() async {
        let store = MediaStore()

        await store.markTaskPending(.waveform)
        let isPending = await store.isTaskPending(.waveform)
        XCTAssertTrue(isPending)

        await store.markTaskComplete(.waveform)
        let isComplete = await store.isTaskPending(.waveform)
        XCTAssertFalse(isComplete)
    }

    func testMediaStoreAnnotations() async {
        let store = MediaStore()

        await store.addTag("favorite")
        await store.setRating(5)
        await store.setNotes("Great video!")

        let annotations = await store.userAnnotations
        XCTAssertTrue(annotations.tags.contains("favorite"))
        XCTAssertEqual(annotations.rating, 5)
        XCTAssertEqual(annotations.notes, "Great video!")
    }

    // MARK: - AnalysisData Tests

    func testWaveformData() {
        let waveform = WaveformData(
            samplesPerSecond: 50,
            minSamples: [-0.5, -0.3],
            maxSamples: [0.5, 0.3],
            channelCount: 1
        )
        XCTAssertEqual(waveform.samplesPerSecond, 50)
        XCTAssertEqual(waveform.count, 2)
        // Test subscript access
        let (min, max) = waveform[0]
        XCTAssertEqual(min, -0.5, accuracy: 0.001)
        XCTAssertEqual(max, 0.5, accuracy: 0.001)
    }

    func testKeyframeIndex() {
        let index = KeyframeIndex(
            times: [0.0, 2.5, 5.0, 7.5],
            frameNumbers: [0, 75, 150, 225]
        )

        XCTAssertEqual(index.nearestKeyframeBefore(time: 3.0), 2.5)
        XCTAssertEqual(index.nearestKeyframeBefore(time: 0.0), 0.0)
        XCTAssertNil(index.nearestKeyframeBefore(time: -1.0))
    }

    // MARK: - Cache Tests

    func testInMemoryCacheStoreRetrieve() async throws {
        let cache = InMemoryMediaCache(maxEntries: 10)
        let key = MediaCacheKey(
            mediaID: MediaID(),
            dataType: .waveform
        )

        let waveform = WaveformData(
            samplesPerSecond: 100,
            minSamples: [0.1],
            maxSamples: [0.5],
            channelCount: 1
        )

        try await cache.store(waveform, for: key)

        let retrieved = try await cache.retrieve(WaveformData.self, for: key)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.samplesPerSecond, 100)
    }

    func testInMemoryCacheEviction() async throws {
        let cache = InMemoryMediaCache(maxEntries: 2)

        let key1 = MediaCacheKey(mediaID: MediaID(), dataType: .waveform)
        let key2 = MediaCacheKey(mediaID: MediaID(), dataType: .waveform)
        let key3 = MediaCacheKey(mediaID: MediaID(), dataType: .waveform)

        let waveform = WaveformData(samplesPerSecond: 100, minSamples: [], maxSamples: [], channelCount: 1)

        try await cache.store(waveform, for: key1)
        try await cache.store(waveform, for: key2)
        try await cache.store(waveform, for: key3)

        // key1 should be evicted
        let retrieved1 = try await cache.retrieve(WaveformData.self, for: key1)
        XCTAssertNil(retrieved1)

        // key2 and key3 should exist
        let contains2 = await cache.contains(key2)
        let contains3 = await cache.contains(key3)
        XCTAssertTrue(contains2)
        XCTAssertTrue(contains3)
    }

    func testCacheStatistics() async throws {
        let cache = InMemoryMediaCache()
        let key = MediaCacheKey(mediaID: MediaID(), dataType: .peak)

        // Miss
        _ = try await cache.retrieve(PeakData.self, for: key)

        // Store and hit
        let peak = PeakData(windowSize: 100, peaks: [0.5, 0.6])
        try await cache.store(peak, for: key)
        _ = try await cache.retrieve(PeakData.self, for: key)

        let stats = await cache.statistics()
        XCTAssertEqual(stats.hitCount, 1)
        XCTAssertEqual(stats.missCount, 1)
        XCTAssertEqual(stats.hitRate, 0.5, accuracy: 0.01)
    }

    // MARK: - Migration Tests

    func testMigrationContext() {
        let context = CYBMediaMigrationContext(
            originalID: UUID(),
            filePath: "/test/video.mov",
            name: "Test Video",
            bookmark: nil,
            wasOffline: false,
            contentTypeIdentifier: "public.movie"
        )

        XCTAssertEqual(context.filePath, "/test/video.mov")
        XCTAssertEqual(context.name, "Test Video")
        XCTAssertFalse(context.wasOffline)
    }

    // MARK: - Probe Tests

    func testAVFoundationProbeSupportedExtensions() {
        let probe = AVFoundationMediaProbe()
        XCTAssertTrue(probe.supportedExtensions.contains("mov"))
        XCTAssertTrue(probe.supportedExtensions.contains("mp4"))
        XCTAssertTrue(probe.supportedExtensions.contains("m4a"))
    }

    func testProbeCanHandle() {
        let probe = AVFoundationMediaProbe()

        let movLocator = MediaLocator.filePath("/test/video.mov")
        XCTAssertTrue(probe.canHandle(locator: movLocator))

        let mkvLocator = MediaLocator.filePath("/test/video.mkv")
        XCTAssertFalse(probe.canHandle(locator: mkvLocator))
    }

    // MARK: - CodecRegistry Tests

    func testCodecRegistryDisplayNames() {
        // H.264
        XCTAssertEqual(CodecRegistry.displayName(for: "avc1"), "H.264")

        // HEVC/H.265
        XCTAssertEqual(CodecRegistry.displayName(for: "hvc1"), "H.265/HEVC")
        XCTAssertEqual(CodecRegistry.displayName(for: "hev1"), "H.265/HEVC")

        // ProRes variants
        XCTAssertEqual(CodecRegistry.displayName(for: "apch"), "Apple ProRes 422 HQ")
        XCTAssertEqual(CodecRegistry.displayName(for: "apcn"), "Apple ProRes 422")
        XCTAssertEqual(CodecRegistry.displayName(for: "ap4h"), "Apple ProRes 4444")

        // Unknown codec returns the input
        XCTAssertEqual(CodecRegistry.displayName(for: "xxxx"), "xxxx")
    }

    func testCodecRegistryCharacteristics() {
        // ProRes 422 family (4:2:2, 10-bit, no alpha)
        let prores422 = CodecRegistry.characteristics(for: "apcn")
        XCTAssertNotNil(prores422)
        XCTAssertEqual(prores422?.chromaSubsampling, .cs422)
        XCTAssertEqual(prores422?.bitDepth, 10)
        XCTAssertEqual(prores422?.hasAlpha, false)

        // ProRes 4444 family (4:4:4, 12-bit, with alpha)
        let prores4444 = CodecRegistry.characteristics(for: "ap4h")
        XCTAssertNotNil(prores4444)
        XCTAssertEqual(prores4444?.chromaSubsampling, .cs444)
        XCTAssertEqual(prores4444?.bitDepth, 12)
        XCTAssertEqual(prores4444?.hasAlpha, true)

        // H.264 (4:2:0, 8-bit, no alpha)
        let h264 = CodecRegistry.characteristics(for: "avc1")
        XCTAssertNotNil(h264)
        XCTAssertEqual(h264?.chromaSubsampling, .cs420)
        XCTAssertEqual(h264?.bitDepth, 8)
        XCTAssertEqual(h264?.hasAlpha, false)

        // Unknown codec returns nil
        XCTAssertNil(CodecRegistry.characteristics(for: "xxxx"))
    }

    func testCodecRegistryReversePlayback() {
        // Intra-frame codecs support reverse playback
        XCTAssertTrue(CodecRegistry.supportsReversePlayback("apch"))
        XCTAssertTrue(CodecRegistry.supportsReversePlayback("mjpb"))

        // Inter-frame codecs do not
        XCTAssertFalse(CodecRegistry.supportsReversePlayback("avc1"))
        XCTAssertFalse(CodecRegistry.supportsReversePlayback("hvc1"))
    }

    // MARK: - CacheValidity Tests

    func testCacheValidityBasic() {
        let validity = CacheValidity(
            version: "1.0",
            sourceBackend: "AVFoundation",
            sourceHash: nil
        )

        // Fresh validity should be valid
        XCTAssertTrue(validity.isValid)
    }

    func testCacheValidityWithHash() {
        let validity = CacheValidity(
            version: "1.0",
            sourceBackend: "AVFoundation",
            sourceHash: "abc123"
        )

        // Matching hash should be valid
        XCTAssertTrue(validity.isValid(withCurrentHash: "abc123"))

        // Different hash should be invalid
        XCTAssertFalse(validity.isValid(withCurrentHash: "xyz789"))

        // Nil current hash with stored hash: falls back to time-based
        XCTAssertTrue(validity.isValid(withCurrentHash: nil))
    }

    func testCacheValidityVersionCompatibility() {
        let validity = CacheValidity(
            version: "2.0",
            sourceBackend: "AVFoundation",
            sourceHash: nil
        )

        // Same or lower version should be compatible
        XCTAssertTrue(validity.isCompatible(withVersion: "2.0"))
        XCTAssertTrue(validity.isCompatible(withVersion: "1.5"))

        // Higher version should be incompatible
        XCTAssertFalse(validity.isCompatible(withVersion: "3.0"))
    }

    // MARK: - CapabilityCalculator Tests

    func testCapabilityCalculatorStaticMethod() {
        // Test that static method works directly without .shared
        let container = ContainerInfo(format: "QuickTime", fileExtension: "mov")

        // Create a minimal descriptor with video
        let descriptor = MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],  // Empty but mediaType is .video
            audioTracks: [],
            probeBackend: "AVFoundation"
        )

        // Use static method directly (not .shared)
        let capabilities = CapabilityCalculator.calculate(
            for: descriptor,
            backend: "AVFoundation",
            analysisState: nil
        )

        // Should have AVFoundation backend capability
        XCTAssertTrue(capabilities.contains(Capability.avFoundationBacked))

        // Should be composable
        XCTAssertTrue(capabilities.contains(Capability.composable))
    }

    func testCapabilityCalculatorWithAnalysisState() {
        let container = ContainerInfo(format: "QuickTime", fileExtension: "mov")
        let descriptor = MediaDescriptor(
            mediaType: .audio,
            container: container,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "AVFoundation"
        )

        // Create analysis state with waveform
        let waveform = WaveformData(
            samplesPerSecond: 100,
            minSamples: [0.1, 0.2],
            maxSamples: [0.5, 0.6],
            channelCount: 1
        )
        let analysisState = AnalysisState(waveform: waveform)

        let capabilities = CapabilityCalculator.calculate(
            for: descriptor,
            backend: "AVFoundation",
            analysisState: analysisState
        )

        // Should have waveform available capability
        XCTAssertTrue(capabilities.contains(Capability.waveformAvailable))
    }

    // MARK: - Timecode Tests

    func testTimecodeExtractionResultInferred() {
        // Test inferred timecode creation
        let result = TimecodeExtractionResult.inferred(frameRate: 24.0)

        XCTAssertEqual(result.start, "00:00:00:00")
        XCTAssertEqual(result.rate, 24.0)
        XCTAssertFalse(result.dropFrame)
        XCTAssertEqual(result.sourceKind, "inferred")
        XCTAssertEqual(result.confidence, 0.3)
    }

    func testTimecodeExtractionResultInferredDefaultRate() {
        // Test inferred timecode with zero frame rate falls back to 30
        let result = TimecodeExtractionResult.inferred(frameRate: 0)

        XCTAssertEqual(result.rate, 30.0)
    }

    func testTimecodeExtractionResultExplicit() {
        // Test explicit timecode creation
        let result = TimecodeExtractionResult(
            start: "01:00:00:00",
            rate: 29.97,
            dropFrame: true,
            sourceKind: "tmcd",
            source: "timecode track 1",
            confidence: 0.95
        )

        XCTAssertEqual(result.start, "01:00:00:00")
        XCTAssertEqual(result.rate, 29.97)
        XCTAssertTrue(result.dropFrame)
        XCTAssertEqual(result.sourceKind, "tmcd")
        XCTAssertEqual(result.source, "timecode track 1")
        XCTAssertEqual(result.confidence, 0.95)
    }

    func testTimecodeAvailabilityEnum() {
        // Test all enum cases exist and are distinct
        let available = TimecodeAvailability.available
        let inferable = TimecodeAvailability.inferable
        let unavailable = TimecodeAvailability.unavailable

        XCTAssertNotEqual(available, inferable)
        XCTAssertNotEqual(inferable, unavailable)
        XCTAssertNotEqual(available, unavailable)
    }

    func testTimecodeCapabilitiesFromTmcd() {
        let container = ContainerInfo(format: "QuickTime", fileExtension: "mov")
        let descriptor = MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "AVFoundation"
        )

        let timecode = TimecodeExtractionResult(
            start: "01:00:00:00",
            rate: 24.0,
            dropFrame: false,
            sourceKind: "tmcd",
            source: "timecode track 1",
            confidence: 0.95
        )

        let capabilities = CapabilityCalculator.calculate(
            for: descriptor,
            backend: "AVFoundation",
            analysisState: nil,
            timecode: timecode
        )

        // Should have timecodeAvailable (not inferable)
        XCTAssertTrue(capabilities.contains(.timecodeAvailable))
        XCTAssertFalse(capabilities.contains(.timecodeInferable))
    }

    func testTimecodeCapabilitiesFromMetadata() {
        let container = ContainerInfo(format: "QuickTime", fileExtension: "mov")
        let descriptor = MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "AVFoundation"
        )

        let timecode = TimecodeExtractionResult(
            start: "00:30:00:00",
            rate: 25.0,
            dropFrame: false,
            sourceKind: "metadata",
            source: "QuickTime metadata",
            confidence: 0.8
        )

        let capabilities = CapabilityCalculator.calculate(
            for: descriptor,
            backend: "AVFoundation",
            analysisState: nil,
            timecode: timecode
        )

        // Metadata source should also set timecodeAvailable
        XCTAssertTrue(capabilities.contains(.timecodeAvailable))
        XCTAssertFalse(capabilities.contains(.timecodeInferable))
    }

    func testTimecodeCapabilitiesFromInferred() {
        let container = ContainerInfo(format: "MPEG-4", fileExtension: "mp4")
        let descriptor = MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "AVFoundation"
        )

        let timecode = TimecodeExtractionResult.inferred(frameRate: 30.0)

        let capabilities = CapabilityCalculator.calculate(
            for: descriptor,
            backend: "AVFoundation",
            analysisState: nil,
            timecode: timecode
        )

        // Inferred source should set timecodeInferable (not available)
        XCTAssertFalse(capabilities.contains(.timecodeAvailable))
        XCTAssertTrue(capabilities.contains(.timecodeInferable))
    }

    func testTimecodeCapabilitiesWithNoTimecode() {
        let container = ContainerInfo(format: "MPEG-4", fileExtension: "mp4")
        let descriptor = MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "AVFoundation"
        )

        let capabilities = CapabilityCalculator.calculate(
            for: descriptor,
            backend: "AVFoundation",
            analysisState: nil,
            timecode: nil
        )

        // No timecode should result in neither capability
        XCTAssertFalse(capabilities.contains(.timecodeAvailable))
        XCTAssertFalse(capabilities.contains(.timecodeInferable))
    }

    func testCoreNormalizedStoreWithTimecode() {
        let container = ContainerInfo(format: "QuickTime", fileExtension: "mov")
        let descriptor = MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "AVFoundation"
        )

        let timecode = TimecodeExtractionResult(
            start: "10:00:00:00",
            rate: 24.0,
            dropFrame: false,
            sourceKind: "tmcd",
            source: "timecode track 1",
            confidence: 0.95
        )

        let store = descriptor.makeCoreNormalizedStore(timecode: timecode)

        // Verify timecode keys are populated
        XCTAssertEqual(store.stringValue(.timecodeStart), "10:00:00:00")
        XCTAssertEqual(store.doubleValue(.timecodeRate), 24.0)
        XCTAssertEqual(store.boolValue(.timecodeDropFrame), false)
        XCTAssertEqual(store.stringValue(.timecodeSourceKind), "tmcd")
        XCTAssertEqual(store.stringValue(.timecodeSource), "timecode track 1")

        // Verify provenance
        let candidates = store.candidates(.timecodeStart)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.provenance.source, "avfoundation:tmcd")
        XCTAssertEqual(candidates.first?.provenance.confidence, 0.95)
    }

    func testExtendedProbeResultMakeCoreNormalizedStore() {
        let container = ContainerInfo(format: "QuickTime", fileExtension: "mov")
        let descriptor = MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "AVFoundation"
        )

        let timecode = TimecodeExtractionResult.inferred(frameRate: 30.0)
        let extendedResult = ExtendedProbeResult(descriptor: descriptor, timecode: timecode)

        let store = extendedResult.makeCoreNormalizedStore()

        // Should have both descriptor and timecode data
        XCTAssertEqual(store.stringValue(.containerFormat), "QuickTime")
        XCTAssertEqual(store.stringValue(.timecodeStart), "00:00:00:00")
        XCTAssertEqual(store.doubleValue(.timecodeRate), 30.0)
        XCTAssertEqual(store.stringValue(.timecodeSourceKind), "inferred")
    }
}
